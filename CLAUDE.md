# Ledge — working notes

Open-source Dynamic Island for macOS. Read this before changing anything; it
records the decisions that aren't obvious from the code and the traps that cost
real time.

## Build and run

```bash
make run     # compile + assemble Ledge.app + relaunch
make test    # 84+ tests across Core, UI, and Modules
make app     # bundle only
make stop    # pkill
```

`swift run` is **not** useful here — the app needs its bundle (Info.plist,
`LSUIElement`, App Intents metadata). Always go through `make`.

## Traps that already bit

**Case-insensitive filesystem, twice.** macOS treats `Ledge` and `ledge` as the
same name.
1. A SwiftPM product named `ledge` collided with the `Ledge` app target's build
   directory and silently compiled the app target's sources into the CLI. The
   product is therefore `ledge-cli`.
2. `cp ledge-cli Ledge.app/Contents/MacOS/ledge` **overwrote the app binary**,
   producing an "app" that was really the CLI and segfaulted on launch. The CLI
   lives in `Contents/Helpers/ledge`. Do not move it back.

**Top-level globals initialise in statement order.** `let ledgeVersion` sat at
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

`LedgeCore` must not import AppKit or SwiftUI — the CLI links it.

## Scheduling semantics

- `.ongoing` persists until ended; `.transient` retires itself (default 1.6s dwell).
- Transients get +10,000 effective priority, so a volume tap cuts in front of music.
- **A transient never occupies the minimal slot.** It takes primary and pushes the
  incumbent to the detached circle. That's what makes a HUD read as an
  interruption rather than a companion. There's a test for it.
- The second slot only ever holds an `.ongoing`.
- Ties break by `updatedAt`, newest first.

## Rendering notes

- `goo` is pulsed only on shape-mode changes (idle/compact/split). A permanent
  blur+threshold pass would soften the fillets for no benefit. The pulse is
  asymmetric: 0 → 16 in 0.16s, back to 0 in 0.30s.
- The expanded panel **measures itself** via `ExpandedHeightKey` rather than being
  estimated from constants. The old estimator drifted the moment fonts changed;
  don't reintroduce it.
- `NotchShape`'s `rect` is the *total* footprint including the fillet flare. The
  solid body is inset by `topFillet` each side.

## Wire protocol

Newline-delimited JSON over `~/Library/Application Support/Ledge/ledge.sock`
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
  using the devices. Ledge never opens the camera or mic.
- Exactly four modules prompt, each independently declinable: Now Playing
  (Automation), Calendar (read-only), Downloads (folder access), and Weather
  (Location — only when first used).
- **The one-and-done rule.** A TCC dialog dismissed by a relaunch stays
  `.notDetermined`, and re-requesting at every launch turns consent into a
  nag (it did — the Calendar dialog haunted the desktop for weeks). A
  prompting module may raise its dialog unsolicited exactly once, ever
  (`permission.<id>.requested` in defaults); after that the prompt only
  comes from the row's Grant Access link in Settings › Modules
  (`SystemProvider.requestPermission()`). Downloads has no queryable TCC
  status, so `.granted` there means "a folder open has verifiably worked"
  (`permission.<id>.verified`). `resetToDefaults` deliberately does NOT
  clear these flags — a settings reset must not resurrect the nag.
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
inode: alive, but every client reports "Ledge isn't running". `stop()` now
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
Finder drag. `ledge shelf <files>` exercises the same shelf code and is tested.

## Visual system

`IslandDesign` is the single source for spacing, type, surface, shadow, and
control styling. Add to it rather than putting point sizes in a view.

The constraint that shapes all of it: **the island overlaps the physical camera
housing, so the top must stay true black.** Depth originates at the bottom edge
and falls downward — hence the theme's `surfaceFill` running dark-to-lighter
going *down*, the opposite of the usual light-from-above treatment. At idle
`hasDepth` is false and the shadow spec is `.none`; anything else shows a seam
where drawn black meets real black.

The silhouette masks a gradient rather than filling one directly:
`alphaThreshold` only works on a flat colour, so the metaball pass produces a
shape that then masks the surface. That's what lets the island have depth *and*
merge like liquid.

## Liquid Glass and motion

The Glass theme's surface is real Liquid Glass on macOS 26+, behind
`if #available` with the material+scrim branch kept verbatim as the fallback
(deployment target stays macOS 14). Decisions that took live experiments:

- **Glass is the PANEL's material; the closed pill is hardware-black.**
  `IslandSilhouette.showsGlass` (the renderer passes `mode == .expanded`)
  fades the glass stack in as the panel grows. With glass active in compact,
  the translucent 6pt lip below the true-black camera strip — plus the
  specular line and the 0.30 rim — read as a strange lit bar bolted under
  the notch ("quite disturbing", verbatim). Compact also drops the rim to
  0.35× for the Glass theme. Settings previews keep `showsGlass: true` so
  the Glass theme card still shows its character.
- **`.clear`, never `.regular`.** Regular glass has an adaptive legibility
  lift that fights a dark tint — over a white desktop it plateaus at mid-grey
  no matter how much black you pour in. `.clear` is the media-context glass:
  transparent, no lift, so the tint (black 0.5) and scrim actually set the
  luminance. `effectiveGlassScrim` (0.26 on 26+) is only the legibility floor;
  the old 0.46 token stays for older systems.
- **One glass sheet, masked.** The glass shape is a plain `.rect`; the
  silhouette mask carves NotchShape, goo, and the detached circle out of it.
  The mask stays the sole shape authority — no per-circle glass, no
  glassEffectID for the merge; the metaball IS the identity. Cost: the glass's
  own edge lensing is clipped away, so the drawn rim and specular line remain
  load-bearing.
- **Glass is what you touch.** Only the action buttons get
  `.glassEffect(...interactive())` (in a `GlassEffectContainer` so a Pause →
  Resume swap morphs); chips, detail panes, and page dots stay ink. In
  settings, NO control is glass — the theme-card selection lozenge was tried
  as glass and *blurred the card's own preview into soup* in Dark Mode; it's a
  matched-geometry tinted fill on every OS.
- **`.glassEffect` works on the island's window.** Verified live: a
  borderless, transparent, non-activating panel at CGShieldingWindowLevel
  samples and refracts the desktop behind it.

Motion rules that came out of the same pass:

- Open and close are different springs (`expand` 0.40/0.80 with a breath of
  overshoot, `collapse` 0.30/0.95 nearly dead). The first expand tuning
  (0.50 + an 80ms content stagger) measured smooth but FELT sluggish on real
  hands — "clunky" was tempo, not framerate; a YDIF frame-difference series
  over a 41fps capture showed zero dropped frames through the spring. The goo
  pulse is asymmetric — fast rise (0.16 easeOut), settle (0.30 easeInOut) —
  and the rim *fades* at the goo threshold instead of blinking.
- **Hover-to-expand requires a RESTING pointer**, not a present one: the
  dwell timer restarts whenever the pointer strays more than 8pt from its
  anchor (`onContinuousHover`), so a pointer in transit to the menu bar never
  opens a panel in its own path. The 2% hover swell was removed for the same
  reason — the island acknowledging every fly-by read as being in the way.
  Transients no longer bounce (`lastArrivalID` is ongoing-only): a volume HUD
  should appear, not celebrate.

## Staying out of the way

An adversarial audit of interruption paths drove a set of rules that are
easy to regress — treat these as invariants:

- **Clicks get the EXACT footprint; slop is for hover only.** `hitTest`
  checks `NSApp.currentEvent` — button events use 0pt slop and no reach
  below the island's bottom edge, and an **idle island is fully
  click-transparent**. Before this, a permanent ~244pt-wide strip below the
  menu bar swallowed clicks in every app, and menu bar items within ~74pt of
  the notch edge were island taps.
- **Drags are gated by location** (`dragIsOverIsland`): AppKit routes drags
  by view geometry, not `hitTest`, so ungated callbacks made the whole
  invisible 648×510 panel a drop target — releasing a file over your own
  document near screen-top fed it to the shelf. The shelf hint also waits
  200ms so a drag merely passing over the notch doesn't erupt.
- **A background tap on the open panel only collapses it.** Opening the
  owning app lives on the header row alone — an accidental hover-expansion
  must never turn the reflex "go away" click into an app switch.
- **Expand pins `focusedActivityID`** so a transient seizing primary can't
  teleport the open panel's content to a volume HUD and back.
- **Goo pulses on mode changes only** (idle/compact/split shape morphs) —
  not on `structureKey`, which fires for content swaps.
- **HUD dwells are 2.0s** (longer than tap–think–tap cadence, so presses
  merge into one episode); the brightness delta threshold is 0.012 so
  ambient auto-brightness ramps never raise the HUD (keyboard steps are
  0.0156+).
- **Hover-expand stands down in full screen** (`hostScreenIsFullScreen`,
  checked on demand — no polling): the shove-to-top "reveal menu bar"
  gesture is a resting pointer in the hit zone, and a panel over a movie is
  the definition of in the way. Click-to-expand still works.
- The arrival bounce is suppressed while the panel is open, and Esc-to-close
  is deliberately NOT implemented: the panel can't become key, and a global
  key monitor would need Accessibility, which the permission posture
  forbids. Outside-click and hover-exit cover dismissal.
- `hoverDelay` default is 400ms; values stored at the old 220 default are
  migrated on load (220 was never a user's choice).
- `contentTransition(.numericText())` does nothing without an animated
  transaction: TimelineView ticks carry none, so every rolling number needs
  `.animation(_, value: label)` next to it. This bug existed on every readout.
- The arrival bounce is a `keyframeAnimator` (trigger: lastArrivalID) —
  retrigger-safe where the old two-`withAnimation` Task clipped when two
  arrivals landed inside 140ms.
- `AnyTransition` has no `.blurReplace`; compose the `Transition`-protocol
  types (`BlurReplaceTransition(configuration: .downUp)`, `ScaleTransition`,
  `OffsetTransition`, `AsymmetricTransition`) — all available at macOS 14.

One test-harness trap: while a human is using the machine, every real click
fires the outside-click monitor and closes the panel — scripted
expand-then-screenshot sequences fail *intermittently* and it looks exactly
like a rendering bug. It isn't. Check for user activity before bisecting.

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
`.ledgeAppearanceChanged` triggers `store.refresh()` so the scheduler re-sorts —
ordering is only recomputed when activities change, so without it the position
slider would do nothing until the next event.

## The glyph family

`LedgeGlyph` is Ledge's own icon set — one 24pt grid, round caps, weight scaled
by the theme. Two weights: `.outline` and `.solid`.

A solid mark is **not the outline filled**. Filling a battery outline gives a
black lozenge, not a battery. Solid variants are different geometry:
a silhouette with its interior detail subtracted.

`paths(in:weight:)` returns **three** paths — stroke, fill, and holes:

- Stroke is linear detail. In the solid weight, *enclosed forms* fill while
  *linear detail stays stroked*: a speaker's cone fills, its sound waves do not.
  Filling everything turns small marks into blobs.
- Holes are punched with `.destinationOut` in a `drawLayer`, **not** an even-odd
  winding. Even-odd also cancels wherever two *intended* solids overlap — a
  music note's stem crossing its head would punch through both.

Two bugs the contact sheet caught that unit tests would not have:
a skip glyph's trailing bar vanished because it was placed in a filled path and
a line has no area; and the solid battery's charge level was drawn into the fill
and then erased by a knockout covering the whole interior. There are now
regression tests for both, but the *sheet* is what found them.

Maintain the set by looking at it: `Ledge.app/Contents/MacOS/Ledge --glyph-sheet
out.png` renders every mark in both weights, side by side. That comparison is
the point — it's how you see whether a solid mark still reads as the same idea
as its outline.

## The settings window

The chrome is an `NSTabViewController` with `tabStyle = .toolbar` — the native
settings idiom. SwiftUI's `TabView` in a plain window renders a centered
segmented control instead, and its tab bar doesn't take synthetic clicks.
The window title is the selected pane's name; each pane has a fixed
`.frame(width: 540, height: …)` and its `NSHostingController` publishes it via
`sizingOptions = [.preferredContentSize]`, which is what animates the window
height between panes.

Rules that keep it behaving like an object rather than a screenshot:

- **The window is built once and never rebuilt.** Deep links flow through
  `SettingsSession` (`@Observable`); the Modules pane watches
  `session.customizing` in `.onAppear`/`.onChange`. Panes register
  UserDefaults-backed state by *reading* `settings.moduleRevision` /
  `appearanceRevision` in `body` — never with an `.id(...)` identity reset,
  and `AppDelegate.setModule` must not poke the window (the old `refresh()`
  teleported an open window to the Modules tab).
- **The app installs a real main menu** even though it's LSUIElement. The
  window promotes the activation policy to `.regular`; with no main menu that
  means an empty menu bar and dead ⌘V/⌘C/⌘W in every field.
- **Grouped-Form section footers align trailing by default on macOS.** Every
  footer goes through `SettingsFooter`, which pins the conventional leading
  block. Easy to miss because a one-line footer looks nearly right.
- The design boundary, stated at the top of `SettingsView.swift`: window
  chrome speaks macOS (SF Symbols, standard controls); anything depicting
  island content speaks Ledge (glyph chips, island previews).
- The customization sheet pins its island preview *outside* the scrolling
  Form, so the thing being tuned never scrolls away.

`ledge settings --tab <name>` and `--customize <module-id>` are real features
and also the only practical way to screenshot these surfaces. A useful side
effect: `--customize` with an unknown id resolves `editing` to nil, which
*closes* an open sheet — the reliable way to dismiss it from a script, since
synthetic clicks on a non-key window's buttons still don't register.

## Adding a module

Each new module is a `SystemProvider` conformance plus a `NativeViewKind` case;
`BatteryProvider` is the simplest complete example, and `TimerProvider` shows
the pattern for one that owns state and persists it. Weather, the settings
window, and per-module customisation are all built — the sections above
describe how they work.
