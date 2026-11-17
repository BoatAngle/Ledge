# Changelog

## 0.3.1

### Fixed
- **The island no longer draws over a full-screen video.** It sits above
  full-screen windows by design — that is what makes it read as hardware — so a
  download finishing put a lit panel across the top of a film with no way to
  dismiss it. It now stands down entirely while a full-screen app owns its
  display, and comes back when you leave.

  The work underneath is untouched: timers keep counting, downloads keep
  tracking, and leaving full screen shows what you missed rather than a gap.
  There is a switch for it in Settings › General › Displays, on by default.

  The guard that was supposed to do this already existed and was dead code. It
  tested whether the menu bar had given up its strip (`visibleFrame`), which —
  measured, not assumed — is simply **not true inside a full-screen Space**. The
  replacement reads the window list: a full-screen app takes its own Space, and
  in that Space the Finder wallpaper and Dock windows vanish. Bounds alone can
  never work, because on a notched Mac a full-screen window and a merely
  maximized one have byte-identical frames.

## 0.3.0

The trust-and-correctness release. A five-lens audit of the whole app found
things the eye doesn't: a clear-the-notch verb that destroyed alarms, an
indicator any local process could switch off, a promise about your location
the code didn't keep.

### Fixed — things that were actively wrong
- **`ledge end-all` and the "Clear the Notch" shortcut destroyed running
  timers.** A timer whose activity vanished was treated as cancelled and
  deleted from disk, so tidying the island silently killed a 25-minute
  alarm — no confirmation, no notice, reachable from a Siri phrase. Clearing
  now spares the built-in modules (`--include-modules` opts back in), and a
  timer whose face is removed simply puts it back. Cancelling still means
  cancelling: the panel's button, the menu bar, or `ledge end <timer-id>`.
- **The camera and microphone indicator could be removed or forged.** Any
  process running as you could `ledge end system.privacy` and the dot stayed
  off for the rest of the call. It now republishes itself the moment it finds
  its activity missing, and the socket refuses to end, update, or impersonate
  anything a module owns.
- **A click on the notch could launch anything on disk.** Activities arriving
  over the socket had their `openURL` handed straight to LaunchServices —
  `file:///Applications/Utilities/Terminal.app` included. External activities
  are now limited to `http`, `https`, and `mailto`, cannot claim a module or a
  native renderer, and cannot outrank a system HUD.
- **The location disclosure was not true.** Three places promised the
  coordinate went "to Open-Meteo and nowhere else" while the code also sent it
  to Apple's geocoder for a city name. The geocoder is gone: the place name now
  comes from the time zone in Open-Meteo's own reply. Coordinates are also
  rounded to about a kilometre, which changes no forecast.
- **The open panel swapped activities under your cursor.** When the thing you
  opened ended, the panel re-targeted to whatever led the sort — so a finished
  download handed you a different activity's buttons mid-click. It closes now.
- **"Show an island on displays without a notch" did nothing.** The one
  preference that could turn off a permanent black pill on a notchless Mac was
  stored, restored, described in Settings, and never read. It works, and takes
  effect immediately rather than at the next launch.
- **A display wake behind the lock screen resumed every poller.** One boolean
  tracked two conditions; nudging the trackpad on a locked Mac restarted
  full-rate polling behind the login window.
- **Action buttons rendered as unreadable smears** in the default theme, on the
  panel every new user sees. `glassEffectID` was tagging a button whose glass
  lived in a detached background layer, so the container lensed the label.
- The settings window often opened behind everything: `NSApp.activate()` is
  cooperative on macOS 14+ and a promoted agent is exactly what the system
  declines to front.
- A stalled socket client wedged every subsequent `ledge` command; connections
  are concurrent now, with a receive timeout.
- Two block-based notification observers were torn down with
  `removeObserver(self)`, which does nothing — one leaked per module toggle.

### Accessibility
- **VoiceOver.** The island is a non-activating panel that can never take
  focus, so arriving activities are announced; the panel's header, detail rows,
  progress, and page dots all carry labels and values.
- **Reduce Motion** replaces the springs, the metaball, the arrival bounce, and
  the two always-on animation loops with short cross-fades.
- **Reduce Transparency** makes the Glass theme's panel a solid object.
- **Increase Contrast** lifts the whole ink ramp. Two steps failed WCAG on
  black even before that — detail labels at ~3.9:1, the page dots at ~1.8:1 for
  a control — and are now 6.2:1 and 3.1:1.
- Camera-and-microphone is no longer pixel-identical to microphone-only: the
  mark becomes two dots, and the colours follow macOS's own convention.

### New
- **A first run.** The app has no Dock icon and no window; on a quiet Mac,
  launching it was indistinguishable from nothing happening. It now introduces
  itself on the island, opens once on its own, and points at the modules —
  and nothing prompts for permission until you turn a module on.
- **Update checking.** Once a day, opt-out, and disclosed in plain words: one
  anonymous request to a public GitHub page, carrying no identifier of any
  kind. A newer version appears in the menu bar and in About.
- The drop target says what it is: the trailing side shows how many files are
  incoming instead of the same breathing dot Focus mode uses.
- Action buttons acknowledge the pointer in all nine themes, not one.
- The hover delay shows its value and no longer reaches zero.

### Energy
- The expiry reaper was a 4 Hz timer running for the life of the process; it is
  now a single timer aimed at the next expiry, and often none at all.
- Every poller's timer carries a tolerance, so the kernel can coalesce nine
  separate wakeups into one.
- The Now Playing script was recompiled once a second — 86,400 identical
  compilations a day. Compiled scripts are cached.
- The outside-click monitor, which woke for every mouse-down anywhere on the
  machine, now exists only while the panel is open.
- Album art no longer accumulates one temp file per track.

## 0.2.0

The "as if Apple designed it" release.

### Themes
- Nine themes, each a whole design language rather than a color swap:
  the Apple-native four (System, Vivid, Glass, Editorial) plus Fluent
  (Windows 11 acrylic), Material (M3 dark), Neon (emissive), Soft (dark
  neumorphism), and Mono (terminal chic, actions as `[bracketed commands]`).
- The Glass theme uses real Liquid Glass on macOS 26+ — `.clear` material,
  masked to the island's metaball silhouette — with the previous material
  as the fallback on older systems.

### Design
- A custom 39-mark icon family in outline and solid weights, drawn on one
  24pt grid; SF Symbol names still work everywhere and fall back cleanly.
- The closed pill is always hardware-black; themes speak in the panel.
- An app icon, drawn from the island's own geometry.

### Feel
- Everything rolls, blurs, or springs: countdown digits roll, panel content
  blurs in behind the shape, open and close are different springs, the
  metaball settles like liquid, arrivals are retrigger-safe.
- The island stays out of the way: clicks get its exact footprint (an idle
  island is click-transparent), drags are location-gated, hover-expand
  requires a resting pointer and stands down in full screen, HUDs merged
  and quieted, and an open panel never gets its content hijacked.
- Permissions are one-and-done: a module asks once, ever; after that,
  granting lives behind an explicit link in Settings.

### Settings
- Native toolbar-pane settings window with live theme cards, per-module
  color/size/position with a live island preview, and real keyboard menus.

### API
- `ledge expand` / `collapse`, settings deep links, and friendlier JSON:
  activities need only a title, actions only an id and a title.

## 0.1.0

First build: the island engine, eleven system modules, the drop shelf,
and the `ledge` CLI / socket API / Shortcuts actions.
