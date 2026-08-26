# CLAUDE.md

Guidance for Claude Code (claude.ai/code) in this repository.

Mindrop — voice capture → transcription → analysis → per-recording mind map.
Flutter app + Node backend + Firebase + Groq. **Local-first** (the phone is the
source of truth; everything cloud is allowed to be late) and **Arabic/English
code-switching is the normal case**, not an edge case.

`README.md` covers first-run setup. This file covers rules and their reasons.

---

## Where things stand

The MVP pipeline works end to end. Since then the work has been a visual identity
migration plus one backend feature. **Read this before assuming a screen or a
feature is in its final state.**

| Area | State |
|---|---|
| All four screens — record, mind map, history, playback | On **Obsidian Crimson**, conversion **complete** |
| Backend (transcribe → analyse) | Working, runs **locally only** |
| Persistent topics | Code committed, **switched off** (no key) |

Identity went neutral-black+orange → Bio-Digital navy → Crimson. Two of the four
category colours are still Bio-Digital survivors, on purpose — see **Design
system**. `MindropColors.accent`/`accentSoft`/`neonTeal`/`neonBlue` were the last
pre-Crimson *accent* tokens, kept alive only by `playback_screen`; that screen
converted, so they are deleted. `textPrimary` / `textSecondary` — the app-wide
chrome neutrals — were the final piece and are **also deleted now**. No token in
`MindropColors` predates Crimson, and the identity migration is fully closed.

### Three switches that are deliberately off

None of these are oversights. Each needs an explicit decision, not a merge.

1. **`OPENAI_API_KEY`** — persistent topics no-op without it. Setting it activates
   a new paid dependency; that is the owner's call. See **Persistent topics**.
2. **`firebase deploy --only firestore:rules`** — the `topics` rule is written in
   `firestore.rules` but not live, so clients would still be denied.
3. **Backend deployment** — `_baseUrl` still defaults to `http://localhost:8787`,
   i.e. the Mac behind `adb reverse`. `render.yaml` sits at the **repo root**,
   which is the only place Render's Blueprint scans; `rootDir: backend` inside it
   points at the service. Ready, but nothing is hosted. Production builds pass
   `--dart-define=MINDROP_API_BASE=…`.

### Not verified, and don't claim otherwise

- **Pinch-to-zoom on the mind map** has never been confirmed with a real gesture.
  `adb` cannot usefully simulate two fingers and single-touch `input` proves
  nothing. Only a human can check it.
- **The mind map frame timings** below predate the Crimson paint path — see the
  warning on that table.
- **Persistent topics has no integration test.** No emulator is configured, so the
  Firestore write shapes are reviewed code, not exercised code.

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

### Deploying to the device — `adb install -r`, never `flutter install`

**`flutter install` destroyed local app data once.** It uninstalls the existing
app *before* checking the target APK exists, so a mode mismatch (it defaults to
release; the build was `--debug`) leaves the app gone and nothing installed. The
uninstall takes app data with it.

`adb install -r` replaces in place and fails safe when the path is wrong.

```bash
adb devices                                  # read the id fresh, never assume
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Back up first — the real data directory is **`app_flutter/`**, not `files/`
(`files/` holds only cached Google Fonts):

```bash
adb exec-out run-as com.mindrop.mindrop tar -czf - app_flutter shared_prefs > ~/Desktop/mindrop_backup.tar.gz
```

`exec-out` rather than staging through `/sdcard` — the app uid cannot reliably
write there. Include `shared_prefs`: it holds the **Firebase anonymous uid**. Lose
that and the reinstalled app mints a new one, orphaning every Firestore document
under the old uid — the transcripts survive in the cloud but the app can't see them.

Judge success from the command's own output and exit code.

---

## Localization

- Every user-facing string goes in **both** `lib/l10n/app_ar.arb` and `app_en.arb`,
  **in the same order**. `app_en.arb` is the template and carries the `@key`
  metadata blocks; `app_ar.arb` carries values only.
- Never hardcode text in widgets. Two deliberate exceptions: the brand string
  `'Mindrop'` (a mark, never translated) and `MaterialLocalizations.of(context)`
  strings such as `backButtonTooltip`, already translated by Flutter.
- Generated `lib/l10n/app_localizations*.dart` are **committed but never
  hand-edited** — change the ARB and regenerate. `flutter run` regenerates;
  **`flutter analyze` does not** — it will report the new key as `undefined_getter`
  on a perfectly correct ARB. Run `flutter gen-l10n` after editing an ARB and
  before trusting analyze. (Corrects an earlier claim here that any `pub get`
  regenerates; it doesn't reliably.)
- Arabic plurals need all six ICU forms (`zero/one/two/few/many/other`).
  `pendingUploads` is the only one today; [widget_test.dart:69](test/widget_test.dart:69)
  fails if someone collapses it to `other`.
- **Fonts are dual-script** — Geist + IBM Plex Sans Arabic, plus JetBrains Mono
  for numerics. All three live in `MindropFonts`; see **Design system** below for
  the whole story, including why Geist went in, came out, and went back in.
- **`TextPainter` inherits no font.** Inside a `CustomPainter` there is no theme,
  so a `TextStyle` without an explicit `fontFamily` silently renders in the
  platform default, not the brand face. This was live for the whole mind map
  before it was caught. Build painter styles with `MindropFonts.style(...)`.
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
  `maxIntrinsicWidth` → clamp → lay out again. See `buildLabel` inside
  `layoutOrganic` in [mind_map.dart](lib/models/mind_map.dart). Skip it and every
  node comes out identical width.

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
  Three traps, all cost real time before they were pinned down:
  - The layer that carries frames is the **`(BLAST)` SurfaceView** one, e.g.
    `<hash> SurfaceView[com.mindrop.mindrop/...MainActivity]@0(BLAST)#<id>`.
    The `MainActivity$_<n>` layer returns the refresh period and **zero rows**.
    The `#<id>` suffix changes on every reinstall — discover it, don't hardcode it.
  - `--latency-clear` **does not clear** on this device. The dump still holds the
    previous burst, so split on the idle gap and read only the last burst.
  - A surface idle for ~1s produces a `33/25/25/33` **wake-from-idle ramp** on the
    next frames. In an aggregate that reads as "20–24% dropped" and is a display
    artifact, not jank. Keep the pipeline warm (a small swipe immediately before)
    or the number is meaningless. Always sanity-check raw ordered intervals before
    believing a percentile.
- Color is never the only signal — status carries icon + label, mind-map category
  nodes carry an icon *and* a written name.

---

## Design system — Obsidian Crimson

Everything visual comes from `MindropColors` and `MindropFonts` in
[app_theme.dart](lib/theme/app_theme.dart). **Never write a literal colour in a
widget.** Source: Stitch's `obsidian_crimson/DESIGN.md`.

This is the third identity. Neutral-black + orange → Bio-Digital (navy, indigo/
teal/amber) → Crimson. The lineage matters because two of the current tokens are
Bio-Digital survivors, on purpose.

### Surfaces are two-tier

`background` `#0A0A0A` is the void; `surface` `#121414` is what components
actually sit on. The previous identity had one flat value because that round only
restyled mind-map *nodes*, not the app. Use `surface` when in doubt — it's what
cards, dialogs and mind-map nodes take.

### One accent, plus neutrals

`crimsonPrimary` `#FFB3B6` is text/icon-safe; `crimsonPrimaryContainer`
`#E11D48` is the live crimson for actions and glow. Neutrals:
`crimsonOnSurface`, `crimsonOnSurfaceVariant`, `crimsonOutline`.

### The four category colours are a compromise — read before "fixing" them

The app needs four distinguishable categories. Crimson ships **one** accent and
two *identical* greys (`#c8c6c5` for both secondary and tertiary). Forcing two
categories into the same grey destroys the point of colour-coding, so:

| Category | Colour | Origin |
|---|---|---|
| tasks | `#44E2CD` teal | Bio-Digital, kept |
| goals | `#F9BD22` amber | Bio-Digital, kept |
| ideas | `#E11D48` crimson | Crimson `primary-container` |
| topics | `#FFB4AB` rose | unchanged — **identical in both exports** |

The root node takes `crimsonPrimary` `#FFB3B6`, and uses it for its **halo only**
(its border is white at 10%).

**Why ideas got `primary-container` and not `primary`:** the literal mapping puts
`#FFB3B6` on ideas, one unit per channel away from topics' `#FFB4AB` — two sibling
categories no eye could separate. The root can safely hold the near-twin because
it never sits beside topics as a sibling. Real Crimson hues for teal and amber
need another Stitch pass; **don't invent hex to close the gap.**

This has now bitten once per palette — Bio-Digital's `primary` vs
`primary-container` failed the same way. The rule: two sibling categories must
never be separated by saturation alone.

### Type: Geist + IBM Plex Sans Arabic + JetBrains Mono

Geist is the Latin face, IBM Plex Sans Arabic the `fontFamilyFallback`. Geist has
no Arabic glyphs, so the engine picks per character and a mixed sentence renders
each script correctly with no switching logic.

JetBrains Mono (`MindropFonts.monoStyle`) is for **numerics only** — the record
timer, the mind-map category counts, the root's timestamp label. It is not a
general text face; don't spread it.

> Geist went in, was reverted in `5ecf9d5`, and went back in here. It was pulled
> because it arrived as scope creep inside a screen-scoped task, **not** because
> the typeface was rejected. Both times the Arabic fallback stayed.

### RTL, per Crimson's own spec

- **Arabic line-height +15%** (`MindropFonts.lineHeight`) so diacritics don't clip
  at the top. Applied where direction is known at build time.
- **Mirror directionally-meaningful icons.** Checked, don't redo this:
  `Icons.arrow_back_rounded` already carries `matchTextDirection: true` and
  mirrors itself. `Icons.play_arrow_rounded` does **not**, so `_StateIcon` in
  [record_button.dart](lib/widgets/record_button.dart) flips it manually. `mic`
  and `stop` aren't directional.
- **Progress fills from the right in Arabic.** This used to be a no-op here,
  on the grounds that "the record waveform is symmetric". It no longer is: the
  live waveform scrolls, so it carries a time direction, and time follows the
  reading direction — newest bar on the right in English, on the left in Arabic.
  `LiveWaveform` reads `Directionality.of(context)` and passes it to the painter
  explicitly (there is no ambient one inside a `CustomPainter`). The playback
  screen still has no playhead of its own to mirror.

### Ignore Crimson's blur

Its `DESIGN.md` names 20–24px backdrop blur as a core pillar. Skip it — same
substitute as always: a `Container` at ~30–40% alpha with a hairline border. The
no-blur rule predates every export and is backed by measurement.

### The waveform's three tones

`crimsonDeep` `#BE0037` (the export's `inverse-primary`) is the third crimson.
The organic waveform needs three separable ribbons and Crimson ships one accent,
so the ramp is **deep → container → primary**, all from the export, none invented.
Stitch's own waveform treatment was not traced — its mockup is a flat two-tone
progress bar, a different object entirely.

The history list briefly walked this same ramp for a per-row mini waveform; that
was removed (see **History screen**), and its row glyph now uses the container
tone alone.

### Conversion is complete — all four screens

`playback_screen` was the last holdout. It is now on Crimson, and
`MindropColors.accent` / `accentSoft` / `neonTeal` / `neonBlue` are **deleted**.
A repo-wide `/usr/bin/grep -r` for their hex values (`FF7A1A`, `FFA24D`,
`2EE6C5`, `4C8DFF`) returns only prose describing the history — one comment in
[pulse_rings.dart:26](lib/widgets/pulse_rings.dart:26) recording why `color`
became required, and this file. No live colour anywhere.

What that round mapped:

| Element | Was | Now |
|---|---|---|
| Waveform, played portion | `accent` | `crimsonPrimaryContainer` |
| Waveform, remaining | `textSecondary` @32% | `crimsonOutline` @32% |
| Seek line | `accent` | `crimsonPrimary` |
| Transcript-arrived icon | `neonTeal` | `crimsonPrimary` |
| Tasks / Goals / Ideas headers | `neonTeal` / `accent` / `neonBlue` | `categoryTeal` / `categoryAmber` / `crimsonPrimaryContainer` |
| Topics header | `textSecondary` | `categoryRose` |
| "Open mind map" button | `accent` | `crimsonPrimary` |
| Play button gradient + glow | `accentSoft → accent` | `crimsonPrimaryContainer → crimsonPrimary` |

Three of those were judgement calls, not lookups:

- **The seek line takes `crimsonPrimary`, not the container tone.** The played
  bars already own `crimsonPrimaryContainer`; a 2px line in the same colour as
  the bars it crosses is invisible, so the playhead takes the lighter sibling.
- **Topics moved off neutral onto `categoryRose`.** It is a fourth category
  exactly like the other three, and the mind map already paints it that way. A
  grey header made it read as a subheading of Ideas rather than a peer. One
  category, one colour, every screen — the same map as `MindMapNode.color`.
- **The play button now matches `record_button.dart`'s gradient order**
  (container → primary, top-left → bottom-right). It previously ran light → dark,
  the opposite way. Two sibling buttons sharing a hue but reversing its direction
  reads as a bug, not as a distinction.

Playback keeps its three `GlassContainer`s (blur 20/18) untouched. That is the
same carve-out the record dock gets: a static screen over a gradient that does
not repaint per frame. **No blur was added** in this round, and none belongs on
a canvas that repaints — see **Performance** and **Mind map**.

### The neutrals are three tiers, not two — and that is the whole trick

`textPrimary` (`#FFFFFF`) and `textSecondary` (`#9A9AA0`) are now **deleted**.
They were held back through every screen round on purpose — app-wide chrome
cannot be converted one screen at a time without opening a new inconsistency —
and were done in a single pass across all 21 read sites once nothing else was
left. `MindropColors` no longer defines a colour that predates Crimson.

The export supplies the replacements; none was invented:

| Tier | Token | Value | Used for |
|---|---|---|---|
| primary | `crimsonOnSurface` | `#E3E2E2` | body copy, titles, user content, back arrows |
| secondary prose | `crimsonOnSurfaceVariant` | `#E5BDBE` | empty states, pending copy, error text |
| meta / muted | `crimsonOutline` | `#AC8889` | timestamps, counts, chips, quiet chrome icons |

**`textSecondary` had to split in two, and skipping that would have been the
real bug.** It was doing two jobs — secondary prose *and* small data readouts —
so mapping it 1:1 onto `crimsonOnSurfaceVariant` collapses the hierarchy:
primary-to-secondary luminance separation drops from **3.08×** to **1.34×**, i.e.
captions come out nearly as bright as the text they sit under. Routing the meta
half to `crimsonOutline` keeps it at **2.70×**, close to the original 3.08×.

The three-tier split is not a new invention either — `history_screen` already
shipped exactly this (`crimsonOutline` on its `label-sm` mono timestamps,
`crimsonOnSurfaceVariant` on its 15pt prose). This pass copied that screen.

Contrast went **up**, not down, everywhere it moved — measured against
`background` `#0A0A0A`:

| | before | after |
|---|---|---|
| primary | 19.80:1 | 15.31:1 |
| secondary prose | 7.07:1 | 10.88:1 |
| meta | 7.07:1 | 6.26:1 |

All well past WCAG AA; primary and secondary clear AAA. The meta tier is the
only one that drops, by 0.8, and it lands at 6.26:1 — still above AA for body
text and far above the 3:1 icons need. That was the price of keeping hierarchy,
and it is the right trade.

---

## Mind map

Scope is **per-recording only**, and that is data-driven: at last check only 3
recordings had analysis, with **zero topics shared** between any two. A
cross-recording map would draw disconnected islands. `MindMapGraph` is already
generic, so adding one later = a new builder + a new layout function, with no
change to the painter, gestures, or direction handling. Don't silently lift the
scope while working in here.

`CustomPainter` + `InteractiveViewer`, `layoutOrganic` — **deterministic by
construction**. Even the organic node wobble is seeded from the node id, so the
same input draws the same shape every run. No physics simulation: the graph is
~17 nodes, and force-directed would add per-run variation and per-frame cost to
solve a problem that doesn't exist.

- Zero `BackdropFilter` on the canvas — **and no `MaskFilter.blur` either**. The
  halos are stacked solid rings at falling alpha: near-identical look, zero
  filter cost. The detail card is a solid `Container` for the same reason — it
  sits above a canvas that repaints. **This is a deliberate deviation from the
  Stitch export**, which specifies `backdrop-blur-md` on every node and
  `blur-xl` on the root halo. We took the result (translucent surface, hairline
  border, glow) and rejected the mechanism. The rule predates the export and is
  backed by measurement; the export is not.
- Text layout and branch ribbons are precomputed. Ribbons are rebuilt per frame
  **only** while the entrance animation runs, because that is the only time their
  endpoints move.
- `GestureDetector` is nested **inside** `InteractiveViewer`, so `localPosition`
  already arrives in canvas coordinates — no manual matrix inversion.

### Visual language

Colour and type now come from **Obsidian Crimson** — see **Design system** above;
don't re-derive them here. The structural decisions below came from the earlier
Bio-Digital pass and survive the rebrand unchanged, because they are about shape
and layout, not palette.

- **All three levels are pills.** Round 1 used deterministic wobbly "blobs" for
  root and category. The export states one shape language — `rounded-full` for
  nodes, `rounded-[3rem]` for the root — so the wobble is gone. A half-organic
  shape isn't a compromise, it's just an undecided one.
- **Connectors are stroked splines**, not tapered filled ribbons: the export
  draws `<path stroke-width="3" fill="none">` at 60% opacity. Cheaper too — one
  path instead of 26 computed edge points.
- **Hierarchy without shape variety**: size, weight, border alpha, and the
  leading glyph. Root = white-10% border + indigo halo (its colour token is the
  *glow*, not the border). Category = accent border + icon + count. Item = accent
  border + colour dot.
- **The dot follows text direction.** "Leading" is the right side in Arabic, so
  the whole content row flips for RTL nodes — same principle as
  `transcript_text.dart`, applied to layout instead of text.
- **Category colours are a documented compromise**, not a clean mapping — the
  detail is in **Design system**. The rule that produced it: two sibling
  categories must never be told apart by saturation alone. That has now bitten
  twice, once per palette.

Each layout rule fixes a real failure:

- **Sector ∝ item count, with a `_minShare` floor.** Pure proportion gave a
  1-task branch 21° beside an 8-idea branch, so its item read as the neighbour's.
- **Radial push-apart after angular placement.** Arc length comes from a fixed
  angle; capsule width comes from user text. A long sentence is ~182pt wide in a
  ~95pt slot — two Ideas capsules literally overlapped. Deterministic push, no simulation.
- **Vertical stretch applied *after* placement**, from measured canvas aspect vs
  viewport. Radial layout yields a ~1:1 canvas in a ~1:1.9 viewport, so width
  always binds and the screen's top and bottom stay empty at any scale. It must be
  after, because final width depends on text measurement.
- **Fit allows scale up to 1.9**, not `min(1.0, …)`. A 3-node map at natural size
  in a large empty screen reads as something that failed to load; letting it grow
  makes a sparse result look deliberate.

### Measured (profile build, 120Hz, 17 nodes / 16 branches)

⚠️ These numbers are from the **round-1 paint path** (blob spline fills + tapered
ribbon fills). The Stitch pass changed paint work — stroked paths, pill RRects,
dot circles — so they are indicative, not current. Re-measure before quoting.

| Case | median | p99 | dropped |
|---|---|---|---|
| Sustained pan | 8.32 ms | 8.32 ms | 1/126 (0.8%) |
| Selection animation | 8.32 ms | 8.32 ms | **0/122** |
| Entrance, mid-animation | 8.32 ms | 8.32 ms | 0 over ~87 frames |

Pan is unchanged from the pre-redesign baseline — that is the point: motion was
added without spending the frame budget.

**One real cost, pre-existing:** opening the screen hitches ~75 ms — first-frame
layout, dominated by 34 `TextPainter.layout()` calls with Arabic shaping. A/B'd
against the pre-redesign build at 83.2 / 74.9 / 83.2 ms over three runs, so it is
not new and is marginally better now. If it ever needs fixing, the target is text
shaping, not geometry.

**Untested:** two-finger pinch-to-zoom has never been verified with a real
gesture. `adb` cannot usefully simulate one, and single-touch `input` proves
nothing about it. Only a human can confirm it — don't claim it works.

---

## Record screen

The home screen, and the one place the app must stay one tap from recording.
**Most of its motion predates the Stitch export** — the breathing button, the
level-reactive halo and the pulse rings all shipped with the MVP. The Stitch pass
was a recolour and a reshape on working code, not a rebuild. The waveform is the
exception: it was replaced outright afterwards, and the reason is below.
Read [record_screen.dart](lib/screens/record_screen.dart) and the three widgets
it composes before assuming any of it is new.

What the Stitch pass actually changed:

- **The button is a droplet.** Per-corner elliptical radii straight from the
  export (`40% 60% 70% 30% / 40% 50% 60% 50%`), in `RecordButton.dropletRadius`.
  It pulls to a full circle on press *and* while recording — `AnimatedContainer`
  lerps the whole `BorderRadius`, so no separate animation drives it.
- **Press is tracked separately from tap** (`onTapDown`/`onTapUp`/`onTapCancel`),
  so the shape answers the finger before recording starts. The icon (mic ↔ stop)
  is still the primary state signal; shape only reinforces it.
- **Gradient and glow are crimson** (`crimsonPrimaryContainer → crimsonPrimary`).
  The original orange `accent` is gone from the codebase entirely — the token
  itself was deleted once playback converted.
- **Pulse rings: two, not four, and indigo.** Two read as a pulse, four as a
  continuous wave. `PulseRings.color` is now **required** — it used to default to
  a hardcoded `Color(0xFFFF7A1A)`, which broke the MindropColors-only rule and
  passed unnoticed because the single caller never passed a colour.
- **Status is two lines**: a headline saying *where you are*, and the original
  hint line saying *what to do*. The hint strings are unchanged, so
  [widget_test.dart](test/widget_test.dart) still finds them.

### Glass here is allowed — don't "fix" it

The dock and the pending chip are real `GlassContainer`s (`BackdropFilter`), and
that is fine: this is the static screen the Performance rule carves out, and what
sits behind them is `AmbientBackground`'s gradient, which does not repaint per
frame. The mind map's no-blur rule exists because *that* canvas repaints on every
finger movement — it is not a blanket ban on the app.

Two consequences worth knowing before adding anything here:

- The Stitch export puts the status caption on its own glass panel. **The dock
  already is that panel**, so the caption went inside it — a translucent panel
  nested in a translucent panel is worse than either. No blur was added.
- The old `organic_waveform.dart` used `MaskFilter.blur` for its glow — a
  *shape* blur, not a backdrop read, so it was allowed under a different rule
  than the mind map's. That file is **deleted**; the live waveform draws flat
  `RRect` bars with no filter of any kind. Nothing on this screen now needs the
  shape-blur carve-out, so don't reintroduce one reasoning from that old note.

### The waveform is real microphone data — do not make it decorative again

[live_waveform.dart](lib/widgets/live_waveform.dart) draws one vertical bar per
**actual amplitude reading**. This replaced `organic_waveform.dart`, which was
three sine ribbons driven by a 7-second `AnimationController`; the real level only
modulated their amplitude, thickness and glow. It moved during silence and its
shape never corresponded to speech. The owner tested it while actually recording
and rejected it for exactly that: they want the native Voice Memos / Samsung
Recorder mechanic, bars that answer the microphone.

**This is the same principle as the history row's deleted hash waveform** (see
**History screen**) and as the transcript hallucination guard: a waveform shape
claims "this is what the audio did", so it must not be generated. The two ideas
have now been rejected once each — a third proposal to make this prettier by
generating the shape is proposing the thing that was already removed twice.

The chain, all of it pre-existing except the widget:

- `record: ^7.1.1` exposes `onAmplitudeChanged(interval)` → `Stream<Amplitude>`,
  `current`/`max` in dBFS. **No new dependency was needed**, and none was added.
- `AudioRecorderService.amplitudeStream()` wraps it;
  `levelStream()` normalises to 0..1. Both already existed and are unchanged.
- `record_screen` owns the ring buffer, because it owns the subscription. The
  widget is stateless and cannot invent a sample the microphone never sent.

Normalisation lives in `levelStream()` and is **adaptive, not a fixed range** —
`autoGain` is on during capture and its whole job is to flatten the gap between a
whisper and a shout, so a fixed −160..0 map yields bars of near-identical height.
Instead: floor −55 dBFS, a peak that jumps instantly upward and decays 0.4 dB per
sample, a 14 dB minimum span so room tone can't fill the screen, `pow(raw, 1.7)`
to widen contrast, then a 0.03 floor so silence still shows a line. Re-tune those
five numbers there, not in the painter.

Fixed choices in the widget, each with a reason:

- **64 bars at 50 ms = a 3.2 s window.** Constant, not derived from width, so the
  shape is identical on any screen; available width is divided by the count.
- **Bars are never animated after they are drawn.** A bar is a record of an
  elapsed 50 ms. Tweening it afterwards would be falsifying the reading. The only
  motion is a new bar entering, one stride every 50 ms.
- **Height is the signal; colour is redundant reinforcement** — the crimson ramp
  `crimsonDeep → crimsonPrimaryContainer → crimsonPrimary` mapped by amplitude,
  the same three export tones the old ribbons used. No new hex.
- **Silence draws a row of dots, not an empty box.** Minimum half-height equals
  half the bar width, so quiet reads as quiet rather than as a broken screen.
- **Pause freezes and dims to 40%; it does not clear.** Those samples really
  happened. `_resetWave()` runs on start and on stop only.

Out of scope and deliberately not built: the export's bottom nav, settings entry
and profile avatar. Mindrop has no screens behind any of them.

---

## History screen ("Your Ideas")

A **list, and a detail view that already existed** — `PlaybackScreen`, reached by
tapping a row, showing waveform, playback, full transcript, analysis and the
mind-map entry. Anyone briefed to "add a transcript detail view" should check
this first.

The Crimson pass added:

- **Date group headers** — "Today" / "Yesterday" / formatted date, compared by
  **calendar day, not elapsed hours** (11pm and 1am are two hours apart and two
  different days). Headers and rows are flattened into one `_Row` list so
  `ListView.builder` stays lazy.
- **A static audio glyph per row** (`Icons.waves_rounded`) — see below for what
  it replaced and why.
- Crimson surfaces, `crimsonOutline` mono timestamps, status colours collapsed
  onto the one-accent system (neutral = waiting, light = moving, vivid = working
  now, white = done, red = failed). The icon and label still carry the meaning;
  colour never carries it alone.

### Don't put a waveform on a list row unless it's real

Round B shipped a per-row mini waveform whose bar heights were hashed from the
recording id — stable per recording, but never matching the audio. It was
**removed** in the next commit and replaced with one static `Icons.waves_rounded`,
identical on every row.

The reasoning is worth keeping, because the idea will come back. A waveform shape
carries a specific claim: peaks and valleys read as *this is what the audio
actually did*. A hash-derived pattern quietly breaks that, however stable it is.
Stitch's mockup hardcodes bar heights too, but Stitch is a static reference image
and Mindrop is a shipping product whose whole premise is not inventing content on
top of what the user said — the same reason the transcript side has a
hallucination guard. A waveform-shaped graphic not derived from the audio is that
problem in miniature.

Drawing the real thing is also blocked from the other side: it means decoding
every audio file inside a scrolling list, which the performance rule exists to
prevent. So the row gets a symbol, which claims nothing.

### Not built, deliberately

- **Timestamped caption blocks.** Stitch's journal panel splits the transcript
  into `00:00` / `02:15` blocks. Mindrop cannot: the backend stores
  `transcript: text` and nothing else. Groq returns per-segment timings in
  `verbose_json` — the hallucination guard already reads them — but they are
  discarded. Captions need a backend change, a Firestore schema change, and
  re-transcription of existing recordings. That is a data feature, not a reskin.
- **The "Resume Recording" bar.** Pause/resume exists only within a live
  recording session; there is no resuming a finished one.
- **The 5-icon bottom nav.** Analytics, settings and profile have no screens.

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
- **Persistent topics run after `saveAnalysis`, never before.** There are no Cloud
  Functions in this repo and no `functions/` directory — the whole pipeline is the
  stateless Express server, and every stage already runs after the 200 has gone back
  to the phone. So this step adds no latency to the save by construction. See
  **Persistent topics** below.

---

## Persistent topics (backend only)

Cross-recording topics: `users/{uid}/topics/{topicId}`, built after a recording's
analysis lands. **Only the topics category participates** — tasks, goals and ideas
stay strictly per-recording, which is the same boundary that keeps
`global_universe_map` out of scope.

- [topicMatcher.js](backend/src/services/topicMatcher.js) is **pure** — cosine
  similarity, the threshold, the create-vs-suggest decision, id generation. No
  network, no Firestore, so it is fully unit-testable without a key or an emulator.
  `SIMILARITY_THRESHOLD` sits at the top of that file; it is **0.83 as a
  placeholder**, not a researched value, and needs tuning against real usage.
- **Nothing auto-links.** Below threshold creates a new topic silently; at or above
  it writes a `topicSuggestion` with `status: 'pending'` and waits. Auto-linking
  would silently merge two different ideas, which is worse than one question.
- **`analysis.topics` stays `string[]`.** The per-item metadata lives in a parallel
  `topicLinks` array on the recording doc. This is not stylistic: the Flutter client
  parses with `whereType<String>()`, so turning items into objects would make every
  topic **silently vanish** from playback and the mind map with no error anywhere.
- Category items have **no stable id of their own**, so `topicLinks[].itemId` is
  derived as `sha1(recordingId|normalizedText|occurrence)`. Array indices were
  rejected — a reorder or partial rewrite would silently repoint them.
- `mergedEmbedding` exists and is tested but **is not called yet**. It is the
  centroid update for the accept path, which is a later round.

### It is off until a key exists

Embeddings need a provider the audio path does not have: Groq has no embeddings
endpoint, and `OPENROUTER_API_KEY` is inert (billing wall, see `transcription.js`).
The code targets OpenAI `text-embedding-3-small` via plain `fetch` — no new npm
dependency — and **no-ops entirely without `OPENAI_API_KEY`**, logging once. Adding
the key is what switches on a new paid dependency, and that is deliberately the
owner's call, not a side effect of this commit.

Every failure in this step is swallowed. The analysis is already written and the
recording already reads `completed` before it runs; the worst outcome is a topic
that does not get created.

### The rule is written but not deployed

`firestore.rules` now has an owner-only `users/{uid}/topics/{topicId}` match. The
backend never needed it (Admin SDK bypasses rules) — it is for the future client,
which would otherwise be denied by default. **Editing the file does not deploy it**;
that needs `firebase deploy --only firestore:rules`, which has not been run.

---

## Verifying before you call something done

Host-only, no device needed, seconds not minutes — run both before claiming
anything works:

```bash
flutter analyze          # baseline: 1 info (unnecessary import, main.dart:1)
flutter test             # baseline: 4/4
cd backend && npm test   # baseline: 13/13 — node:test, no extra deps
```

`flutter analyze` does **not** regenerate localizations; run `flutter gen-l10n`
after editing an ARB or it reports a correct key as `undefined_getter`.

The backend suite covers the topic matcher's pure logic only — deliberately no
network and no Firestore, so it needs neither a key nor an emulator.

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

- The `FirestoreSyncService` class doc and the `backend/src/server.js` header both
  describe a pre-backend world that no longer exists. Trust the code.
- `flutter analyze`'s only finding: unnecessary `flutter/foundation.dart` import at
  [main.dart:1](lib/main.dart:1). Baseline is 1 info, 0 warnings; `flutter test` is 4/4.
- Release builds still sign with the debug keys (`android/app/build.gradle.kts`).
