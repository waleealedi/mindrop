# CLAUDE.md

Guidance for Claude Code (claude.ai/code) in this repository.

Mindrop — voice capture → transcription → analysis → per-recording mind map.
Flutter app + Node backend + Firebase + Groq. **Local-first** (the phone is the
source of truth; everything cloud is allowed to be late) and **Arabic/English
code-switching is the normal case**, not an edge case.

`README.md` covers first-run setup. This file covers rules and their reasons.

---

## Git

- **Commit and push after every completed task**, not at the end of a session.
- Small commits. The message says **why**, not just what — the diff already says what.
- Work happens directly on `master` (`origin` = `github.com/waleealedi/mindrop`, private).

**Never commit:** `backend/.env`, `backend/service-account.json`, `backend/storage/`.
Ignored at *both* the root and `backend/` level, duplicated on purpose so the
protection can't vanish if one file moves.

**Committed on purpose:** `lib/firebase_options.dart`, `android/app/google-services.json`.
Firebase client keys identify a project, they don't authorize access — Firestore
Rules are the boundary, and both files ship inside the APK regardless.

### ⚠️ Secret scans: use `/usr/bin/grep -r`

**Correction to the note this rule came from:** the wrapper is **`rg`, not `grep`**.
`grep` resolves to `/usr/bin/grep` in this shell. `rg` is a shell function (Claude
Code integration) and inherits ripgrep's defaults, which **skip gitignored and
hidden files** — i.e. exactly `.env` and `service-account.json`, silently, with
no error. Reproduced here:

```bash
rg -l "GROQ_API_KEY" .              # misses backend/.env
/usr/bin/grep -rl "GROQ_API_KEY" .  # finds it
```

Same conclusion, right mechanism: any secret audit calls `/usr/bin/grep -r` explicitly.

---

## Dev environment

### `adb reverse` — check this before diagnosing ANY upload failure

The phone resolves `localhost` as itself, not the Mac. The tunnel is wiped by
**any** adb daemon restart: USB replug, sleep, `adb kill-server`, or any tool
that touches the daemon.

```bash
adb reverse --list                  # FIRST command. Empty = this is the cause.
adb reverse tcp:8787 tcp:8787       # restore
```

`curl localhost:8787/health` from the Mac proves nothing about what the phone
can reach. Test from the phone: `adb shell curl -s http://localhost:8787/health`.

**Check the backend and the tunnel independently — don't assume both are down.**
A live server behind a dead tunnel is indistinguishable from a dead server, from
the app's side. (Last verified state: backend *up*, tunnel *empty*.)
One server only: `pkill -f "src/server.js"` clears strays holding 8787.

Diagnose without rebuilding: `adb logcat -c`, close and reopen the app, then
`adb logcat -d | grep -a "رفع التسجيل"` — every upload failure prints under that prefix.

### Device & machine

Physical device only: `R5CY821BZQF` (SM-S938B, Android 16 / **API 36**). No
emulator — the dev machine is an 8GB MacBook Air M2.

`network_security_config.xml` permits cleartext for `localhost` / `127.0.0.1` /
`::1` / `10.0.2.2` **only**. Android blocks cleartext since API 28, and the
automatic localhost exception ships from API 37 — this device is 36. Never
replace it with `usesCleartextTraffic="true"`; that opens HTTP to every host.

---

## Localization

- Every user-facing string goes in **both** `lib/l10n/app_ar.arb` and `app_en.arb`,
  **in the same order**. `app_en.arb` is the template and carries the `@key`
  metadata blocks; `app_ar.arb` carries values only.
- Never hardcode text in widgets. Two deliberate exceptions: the brand string
  `'Mindrop'` (a mark, never translated) and `MaterialLocalizations.of(context)`
  strings such as `backButtonTooltip`, already translated by Flutter.
- Generated `lib/l10n/app_localizations*.dart` are **committed but never
  hand-edited** — change the ARB and regenerate. `flutter pub get` / `flutter run`
  regenerate automatically; there is no separate codegen step.
- Arabic plurals need all six ICU forms (`zero/one/two/few/many/other`).
  `pendingUploads` is the only one today; [widget_test.dart:69](test/widget_test.dart:69)
  fails if someone collapses it to `other`.
- **Always** `import 'package:intl/intl.dart' show DateFormat;` (or `show Bidi;`).
  A bare import shadows Flutter's `TextDirection` with intl's own class. Extend
  the `show` list; never drop it.

---

## Text direction — has broken things twice

**UI chrome follows the app locale. User content follows its own language.**
User content = transcripts, extracted tasks/goals/ideas/topics, mind-map node labels.

- Route all of it through [transcript_text.dart](lib/widgets/transcript_text.dart),
  which calls `Bidi.detectRtlDirectionality` and derives **both** `textDirection`
  and `textAlign` from it. An Arabic string left-aligned looks nearly as broken
  as one in the wrong direction.
- Every numeric/time display needs explicit `textDirection: TextDirection.ltr`,
  or `"01:20"` renders as `"20:01"` in RTL. Applied in the record timer, history
  duration, both playback times.
- Inside a `CustomPainter` there is **no ambient `Directionality`** —
  `TextPainter` requires an explicit `textDirection` every time, and inherits nothing.
- `TextPainter.width` returns the **layout constraint**, not the rendered text
  width. Two-pass layout is required: lay out at max width → read
  `maxIntrinsicWidth` → clamp → lay out again. See `layoutRadial` in
  [mind_map.dart](lib/models/mind_map.dart). Skip it and every node comes out identical width.

---

## Performance

- **No `BackdropFilter` / `GlassContainer` inside a long `ListView`, or above any
  surface that repaints per frame.** Each one re-reads everything behind it every
  frame. Fine on a single static screen; cap at 3–4 per screen. The history card
  uses a plain `Container` at `alpha: 0.26`; the ambient background uses
  `RadialGradient`, not blur — near-identical visually, near-zero cost.
- `android/gradle.properties` is **deliberately reduced** (`-Xmx1536m`, metaspace
  512m, `kotlin.daemon.jvmargs=-Xmx768m`, `workers.max=2`). Flutter's template asks
  for ~12GB and drives an 8GB machine into swap. **Never restore the defaults.**
- `cd android && ./gradlew --stop` after every `flutter run` — the daemon otherwise
  sits on 1–2GB.
- Measure animation on the real device via SurfaceFlinger present times.
  `dumpsys gfxinfo` returns **0 frames** for Flutter (it draws to its own surface).
- Color is never the only signal — status carries icon + label, mind-map category
  nodes carry an icon *and* a written name.

---

## Cloud writes vs deletes — opposite policies on purpose

**Writes are best-effort and fail silently.** Local work must never be blocked by
the network. Worst case: the cloud is briefly behind, and the next sync fixes it.

**Deletes are not.** A silent delete failure erases the local record while the
cloud copy survives — the user can no longer see the thing they wanted gone, so
they can't retry. Silence there *is* the bug. This was real: 20 cloud documents
against 3 local drafts, 4 orphans still holding transcribed personal text.

[deletion_queue_service.dart](lib/services/deletion_queue_service.dart):

- **Tombstone written to disk BEFORE the local delete.** Reverse the order and a
  crash in between leaves an orphan with no trace anyone wanted it gone.
- Not cloud-first either — that breaks offline deletion, which contradicts local-first.
- Retried on the same triggers as uploads: app start, app resume, after every upload cycle.
- `FirestoreSyncService.deleteRecordings` **throws on failure**, unlike `syncMetadata`.
  The caller must know the result to decide whether to keep the tombstone.
- **20s cap on `batch.commit()`** — offline it does *not* throw; Firestore queues
  it and leaves the Future pending forever, which used to pin `_isRunning` true
  and kill all later sync. Re-deleting a deleted doc is a no-op, so retry is safe.
- Batches chunk at **400**. Current docs define no per-batch *operation* limit
  (limits are 10 MiB/request and 500 *field transforms per document*). 400 is a
  deliberate margin — don't "correct" it to the obsolete 500-operation figure.
- Residual limitation, accepted: between an offline delete and reconnection the
  cloud copy still exists. The tombstone bounds that window; it can't eliminate it.

---

## Pipeline & sync

`recorded → uploading → uploaded → transcribing → analyzing → completed`, with
`failed` reachable from any stage and always retryable. The app writes local
metadata and the backend writes results into the **same** Firestore doc
(`users/{uid}/recordings/{id}`), always with `{merge: true}`.

- **Never prefer remote status unconditionally.** `syncMetadata` writes `recorded`
  at *creation*, so remote can be **behind** local. `mergedRecordingStatus`
  ([recording_draft.dart:47](lib/models/recording_draft.dart:47)): `completed`
  wins over everything (durable proof, and retries are supported) → else `failed`
  wins over any in-progress state (a hidden failure means the user believes a lost
  idea is saved) → else higher `pipelineRank`. Add new stages to `pipelineRank` only.
- **Upload failure classification.** `package:http` 1.6.0 ships no default timeout,
  so a hung socket froze the queue forever; hence a 3-minute cap. Transient
  (`TimeoutException`, `SocketException`, `ClientException`, `HandshakeException`,
  **5xx**) → back to `recorded`, `retryCount` **not** incremented — a sleeping free
  host is waiting, not failing. Everything else → `failed`, `retryCount += 1`.
- Backend is **stateless by default**: receive → transcribe → analyse → write
  Firestore → discard audio in a `try/finally`. `KEEP_AUDIO=1` is dev-only and off
  by default so local dev exercises the production path. Turn it on and
  `backend/storage/` accumulates transcribed personal audio until cleaned manually.
- Duplicate detection lives in **Firestore, not on disk** — an ephemeral disk loses
  the marker on every redeploy, silently re-transcribing and re-paying.
- **Never send `language` to Groq.** Auto-detection is the entire point for
  code-switched speech. The hallucination guard in
  [transcription.js](backend/src/services/transcription.js) rejects output instead:
  mean `avg_logprob < -1.0`, detected language outside `{arabic, english}`, or
  punctuation-only. `no_speech_prob` was 0.0000 on all seven test samples
  *including both failures* — it has no discriminating power here; the `0.9` check
  is a never-fired safety net. Detected language was the only signal that caught
  a clip transcribed as Korean.
- Analysis schema is four required string arrays with **no optional fields** — every
  optional field invites the model to invent a value nobody said, and a hallucinated
  task is the worst failure this product can produce.

---

## Code style

- **Arabic comments are intentional and document *why*, usually after a real bug.**
  Never translate or strip them. Match that style in new comments.
- Match surrounding style. No new dependencies without justification.
- Colors come from `MindropColors` only — never literal colors in widgets.
- Firestore listeners are tied to their screen's lifecycle — never a one-shot read
  for data that changes, never an app-level singleton (Firestore bills per document
  delivered).

---

## Known inconsistencies (flagged, not fixed)

- `backend/.env.example` omits `GROQ_API_KEY`, though both services point users to
  that file when the key is missing.
- The `FirestoreSyncService` class doc and the `backend/src/server.js` header both
  describe a pre-backend world that no longer exists. Trust the code.
- `flutter analyze`'s only finding: unnecessary `flutter/foundation.dart` import at
  [main.dart:1](lib/main.dart:1). Baseline is 1 info, 0 warnings; `flutter test` is 4/4.
- Release builds still sign with the debug keys (`android/app/build.gradle.kts`).
