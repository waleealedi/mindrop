# Mindrop

Capture a spoken thought, get it back organised.

You tap once and talk. Mindrop saves the audio locally, uploads it, transcribes
it, and extracts the **tasks, goals, ideas and topics** inside it — then shows
them as text and as a per-recording mind map.

Two things shape almost every design decision in this codebase:

- **Local-first.** The phone is the source of truth. Recording, playback,
  browsing and deleting all work with no network and no backend running.
  Everything cloud is layered on top and is allowed to be late.
- **Arabic/English code-switching is the normal case,** not an edge case. The
  user speaks both, often in one sentence. Language is auto-detected per
  recording and never forced, and text direction is derived from *content*, not
  from the app's locale.

> Most comments in this repo are in Arabic. They are deliberate and they explain
> **why** a decision was made, usually after a real bug. Don't translate or strip
> them.

---

## Architecture

```
Flutter app (phone)                     Node backend
  record → DraftStore (local)             POST /recordings/:id
         → upload queue        ────────►   verify Firebase ID token
         → Firestore listener  ◄────────   transcribe (Groq Whisper)
                                           analyse   (Groq LLM)
                                           write transcript + analysis
                                           discard the audio
```

The backend is **stateless by design**: it holds the audio only while
processing, then deletes it. Free hosts have ephemeral disks, and the phone
already has the durable copy.

| Piece | What it is |
|---|---|
| Transcription | Groq `whisper-large-v3-turbo` — no `language` parameter, ever |
| Analysis | Groq `openai/gpt-oss-120b`, JSON-schema structured output |
| Auth | Firebase Anonymous Auth; backend verifies the ID token |
| Data | Firestore `users/{uid}/recordings/{id}` — owner-only rules |

---

## Running it

### 1. Backend

```bash
cd backend
npm ci
npm run dev          # http://localhost:8787
```

Create `backend/.env` from `backend/.env.example`:

| Variable | Required | Where to get it |
|---|---|---|
| `PORT` | no | Defaults to `8787` |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | local dev | Firebase Console → Project Settings → Service Accounts → **Generate new private key**. Save as `backend/service-account.json` |
| `FIREBASE_SERVICE_ACCOUNT_B64` | production | `base64 -i service-account.json`. Used instead of the file path on hosts with no disk — base64 because the PEM's newlines get mangled by env-var UIs |
| `GROQ_API_KEY` | yes | <https://console.groq.com> — free tier, no card |
| `KEEP_AUDIO` | no | `1` keeps audio + `<id>.json` on disk for local re-runs. **Off by default** so dev matches production |

`OPENROUTER_API_KEY` is only used by `transcribeViaOpenRouter()`, which is kept
intact but inactive — see the comment in `backend/src/services/transcription.js`.

### 2. App

```bash
flutter pub get
flutter run -d <device-id>
```

Against a deployed backend, pass the URL at build time instead of editing source:

```bash
flutter build apk --release --dart-define=MINDROP_API_BASE=https://your-host
```

### 3. ⚠️ `adb reverse` — read this before debugging any upload

A physical Android device resolves `localhost` as **itself**, not your Mac. The
app will not reach your backend without a USB tunnel:

```bash
adb reverse tcp:8787 tcp:8787
```

**This has cost hours three separate times.** It silently disappears whenever
the adb daemon restarts, the cable is replugged, or the device reconnects — and
the only symptom is uploads failing with connection-refused while everything
looks fine on the Mac.

So when an upload misbehaves, check this **first**, before reading any code:

```bash
adb reverse --list      # empty output means the tunnel is gone
```

Testing `http://localhost:8787/health` in the Mac's browser proves nothing —
it only shows the Mac can reach the Mac. To test from the phone's point of view:

```bash
adb shell curl -s http://localhost:8787/health
```

### 4. Firestore rules

```bash
firebase deploy --only firestore:rules
```

Rules restrict `users/{uid}/recordings/{id}` to its owner. That — not the API
key — is the security boundary.

---

## Secrets

`backend/.env`, `backend/service-account.json` and `backend/storage/` are
git-ignored at both the root and `backend/` level, deliberately duplicated so
the protection can't vanish if one file is moved.

`lib/firebase_options.dart` and `android/app/google-services.json` **are**
committed. Firebase client API keys identify a project, they don't authorise
access; Google documents them as safe to include in client code.

**Firestore Rules are the only client-side boundary. App Check is _not_
enabled** — there is no App Check code anywhere in this repo. An earlier version
of this section claimed otherwise; it was wrong.

What that means concretely: sign-in is anonymous and the client key ships inside
the APK, so anyone can mint a *legitimate* ID token for this project. The token
proves "an account in this project", not "the owner of this app". Firestore Rules
still hold — each uid can only read and write its own documents — but they place
no ceiling on how many documents an attacker can create under a uid of their own.

The backend's own guard is therefore a cost guard, not an identity one: a
per-uid rate limit on `POST /recordings/:recordingId`
(`backend/src/middleware/uploadRateLimit.js`), since every accepted upload buys a
Whisper call and an LLM call on the owner's account. It is an in-memory counter,
so a restart resets it. Enabling App Check, or moving the counter to a shared
store, are both still open.
