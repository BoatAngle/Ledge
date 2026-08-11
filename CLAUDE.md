# Islet — working notes

Open-source Dynamic Island for macOS. Read this before changing anything; it
records the decisions that aren't obvious from the code and the traps that cost
real time.

## Build and run

```bash
make run     # compile + assemble Islet.app + relaunch
make test    # 69 tests across Core, UI, and Modules
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
- Exactly three modules prompt, each independently declinable: Now Playing
  (Automation), Calendar (read-only), Downloads (folder access).
- No Full Disk Access. Downloads are read from the partial files in
  `~/Downloads`, not from Safari's container.

## Private API

Exactly one: `DisplayServicesGetBrightness`, `dlopen`'d by name in
`DisplayServicesBridge`. There is no public way to read display brightness. It is
isolated to that file and fails to `isAvailable == false`. Keep it contained.

## Deferred startup is mandatory

Providers start inside a `Task` in `applicationDidFinishLaunching`, never inline.
Several touch TCC-gated resources (Downloads, Calendar, Apple Events), and
raising a consent prompt *during* launch deadlocks: the app hasn't finished
launching, so the prompt can't be presented, so launch never finishes. It
presents as a hang with no crash log, and running the binary from a terminal
hides it completely because the process inherits the terminal's permissions.

For the same reason `DownloadsProvider` opens `~/Downloads` on a background
queue — the blocking `open()` would otherwise freeze the island, the menu bar
item, and the API for as long as the dialog sits there — and `isAvailable` never
stats the folder.

## Two more traps

**The socket unlink race.** On quit the server used to `unlink` the socket
unconditionally. Relaunching overlaps the two processes, so the outgoing app
would delete the *incoming* one's socket, leaving it listening on an unreachable
inode: alive, but every client reports "Islet isn't running". `stop()` now
compares the inode before unlinking.

**The footprint race.** `PassthroughHostingView.hitTest` rejects everything when
`footprint` is zero, which makes the island completely inert with no visible
symptom. The root view's callback writes through `hostingView`, so that
reference must be assigned *before* the real root view is installed — hence the
placeholder-then-swap in `rebuild()`, plus `fallbackFootprint`.

## Testing hover

`CGWarpMouseCursorPosition` moves the pointer without posting an event, so
tracking areas never fire and `.onHover` looks broken when it isn't. Post a real
event instead:

```swift
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
```

Dragging files *onto* the notch can't be scripted safely — it needs a real
Finder drag. `islet shelf <files>` exercises the same shelf code and is tested.

## Visual system

`IslandDesign` is the single source for spacing, type, surface, shadow, and
control styling. Add to it rather than putting point sizes in a view.

The constraint that shapes all of it: **the island overlaps the physical camera
housing, so the top must stay true black.** Depth originates at the bottom edge
and falls downward — hence `surfaceFill(liftsAtBottom:)` running dark-to-lighter
going *down*, the opposite of the usual light-from-above treatment. At idle
`hasDepth` is false and the shadow spec is `.none`; anything else shows a seam
where drawn black meets real black.

The silhouette masks a gradient rather than filling one directly:
`alphaThreshold` only works on a flat colour, so the metaball pass produces a
shape that then masks the surface. That's what lets the island have depth *and*
merge like liquid.

## Per-module appearance

`ModuleAppearance` (tint, scale, slot, priority offset) is stored per module as
JSON in `UserDefaults` under `appearance.<id>`. Three things to know:

1. `Activity.module` is what appearance keys off — not `id`, because one module
   posts many activities (every running timer is its own).
2. Slot preference is applied as **priority bias**, not a separate placement
   pass. One ordering rule, not two.
3. Decoding clamps. These values are user-writable via `defaults write`, and a
   scale of 40 would put a glyph clean off the notch.

Changing appearance has to reach two places: the renderer reads
`settings.appearanceRevision` so `@Observable` registers a dependency it
otherwise couldn't (the data lives in `UserDefaults`), and
`.isletAppearanceChanged` triggers `store.refresh()` so the scheduler re-sorts —
ordering is only recomputed when activities change, so without it the position
slider would do nothing until the next event.

## Settings deep links

`islet settings --tab weather` and `islet settings --customize system.media`
exist partly because synthetic clicks on a SwiftUI `TabView` tab bar and on
`Form` row buttons do not reliably register on a non-key window. They are real
features, and also the only practical way to screenshot those surfaces.

## Not yet built

Weather, a settings window, and per-module customisation (colours, sizes,
positions). Each new module is a `SystemProvider` conformance plus a
`NativeViewKind` case; `BatteryProvider` is the simplest complete example, and
`TimerProvider` shows the pattern for one that owns state and persists it.
