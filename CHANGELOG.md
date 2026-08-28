# Changelog

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
