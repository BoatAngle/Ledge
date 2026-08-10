# Islet — working notes

Open-source Dynamic Island for macOS. Read this before changing anything; it
records the decisions that aren't obvious from the code and the traps that cost
real time.

## Build and run

```bash
make run     # compile + assemble Islet.app + relaunch
make test    # 30 tests over IsletCore
make app     # bundle only
make stop    # pkill
```

`swift run` is **not** useful here — the app needs its bundle (Info.plist,
`LSUIElement`, App Intents metadata). Always go through `make`.

## Traps that already bit

**Case-insensitive filesystem, twice.** macOS treats `Islet` and `islet` as the
same name.
1. A SwiftPM product named `islet` collided with the `Islet` app target's build
   directory and silently compiled the app target's sources into the CLI. The
   product is therefore `islet-cli`.
2. `cp islet-cli Islet.app/Contents/MacOS/islet` **overwrote the app binary**,
   producing an "app" that was really the CLI and segfaulted on launch. The CLI
   lives in `Contents/Helpers/islet`. Do not move it back.

**Top-level globals initialise in statement order.** `let isletVersion` sat at
the bottom of the CLI's `main.swift` and `printUsage()` read it from above —
uninitialised memory, segfault. It lives in `Arguments.swift` now. Never declare
a global below the code that uses it in a `main.swift`.

**`NSHostingView` centres its content.** The island's frame is much smaller than
the panel, so it rendered in the middle of the screen. `IslandHostView` wraps it
in a `VStack` + `Spacer` pinned to `.top`.

**ZStack alignment must be `.topLeading`.** Centring works for the symmetric
compact state and silently mis-places everything in `.split`, where the body is
narrower than the footprint. The silhouette's oversized blur canvas made this
worse — it drew ~30pt left of true.

## Architecture rule

`ActivityStore.recompose()` is the only place that decides what appears and in
which slot. Views read `store.composition` and render it. If you find yourself
adding display logic to a view that depends on *which* activities exist, it
belongs in the store.

`IsletCore` must not import AppKit or SwiftUI — the CLI links it.

## Scheduling semantics

- `.ongoing` persists until ended; `.transient` retires itself (default 1.6s dwell).
- Transients get +10,000 effective priority, so a volume tap cuts in front of music.
- **A transient never occupies the minimal slot.** It takes primary and pushes the
  incumbent to the detached circle. That's what makes a HUD read as an
  interruption rather than a companion. There's a test for it.
- The second slot only ever holds an `.ongoing`.
- Ties break by `updatedAt`, newest first.

## Rendering notes

- `goo` is pulsed only on structure changes. A permanent blur+threshold pass
  would soften the fillets for no benefit. `GooDriver.pulse()` runs it 0 → 16 → 0
  over 420ms.
- The expanded panel **measures itself** via `ExpandedHeightKey` rather than being
  estimated from constants. The old estimator drifted the moment fonts changed;
  don't reintroduce it.
- `NotchShape`'s `rect` is the *total* footprint including the fillet flare. The
  solid body is inset by `topFillet` each side.

## Wire protocol

Newline-delimited JSON over `~/Library/Application Support/Islet/islet.sock`
(0600, in a 0700 directory). One request per connection.

Dates use ISO 8601 **with fractional seconds** via `Date.ISO8601FormatStyle`.
Plain `.iso8601` truncated to whole seconds and rounded `--dwell 1.5` down to 1.
The decoder accepts both forms so hand-written JSON still parses.

`ActivityContent` has a hand-written `init(from:)` so `details` and `actions` are
optional. Requiring `{"title":"Hi","details":[],"actions":[]}` as the minimum
payload would defeat the point of a scriptable API.

## Permissions posture

Deliberate, and worth preserving:
- Caps Lock polls `NSEvent.modifierFlags`; a global key monitor would need
  Accessibility.
- Privacy indicators query CoreAudio/CoreMediaIO for whether *someone else* is
  using the devices. Islet never opens the camera or mic.
- Only the media module prompts for anything (Automation, for Music/Spotify).

## Private API

Exactly one: `DisplayServicesGetBrightness`, `dlopen`'d by name in
`DisplayServicesBridge`. There is no public way to read display brightness. It is
isolated to that file and fails to `isAvailable == false`. Keep it contained.

## Not yet built

Calendar, timers, AirDrop shelf, download tracking, lock-screen presence. The
activity model already expresses all of them — each is a `SystemProvider`
conformance plus a `NativeViewKind` case. Start from `BatteryProvider`, which is
the simplest complete example.
