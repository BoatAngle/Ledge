# Islet

A Dynamic Island for macOS — and a live-activity API for everything else on your Mac.

Islet turns the MacBook notch into the thing Apple built for the iPhone: a small
black shape that grows when something happens, splits when two things happen at
once, and drops down into a panel when you want the detail. It ships the system
modules you'd expect, and then goes one step further — **anything on your Mac can
post its own activity to the notch.**

```bash
islet run --title "Build" -- swift build
```

MIT licensed. No account, no license key, no subscription, no telemetry.

---

## What it does

**The island itself**, modelled on Apple's actual presentation system rather than
approximated:

| State | When |
|---|---|
| `idle` | Nothing happening — invisible against the hardware |
| `compact` | One activity, a glyph either side of the camera |
| `split` | Two at once — a compact pill plus a detached circle |
| `expanded` | The drop-down panel |

Transitions run on springs, and the split/merge goes through a metaball filter so
the shapes stretch apart like liquid instead of snapping. Concave fillets join
the island to the top bezel, which is what sells it as carved out of the display
rather than pasted on top.

The surface treatment works around one hard constraint: the island overlaps the
physical camera housing, so its upper region has to be indistinguishable from
the bezel. All the depth — the surface gradient, the specular rim, the layered
contact-and-ambient shadows — originates at the bottom edge and falls away
downward. At idle it's suppressed entirely, because the island *is* the notch
and any deviation from true black would show as a seam.

Works on notchless Macs and external monitors too — it draws a virtual island of
the same dimensions.

**System modules**, all optional, all toggleable from the menu bar:

- **Now Playing** — Apple Music and Spotify, with album art, a live waveform, and transport controls
- **Timers** — countdowns that ring, survive a restart, and tick without any updates being sent
- **Calendar & Events** — your next meeting as it approaches, with a Join button that finds the video link wherever the invite hid it
- **Downloads** — in-progress downloads from any browser, and a completion notice
- **Drop shelf** — drag files onto the notch to park them, then drag them back out, AirDrop, or reveal in Finder
- **Battery & Charging** — announces plug-in, low-battery thresholds, and full charge
- **Sound & Output Device** — volume HUD, plus "your AirPods just connected"
- **Display Brightness** — brightness HUD
- **Focus** — the active Focus, persistently but quietly
- **Caps Lock** — a small confirmation
- **Weather** — current conditions from Open-Meteo, which needs no account or API key
- **Camera & Microphone** — privacy indicators the moment something starts using them

Everything stands down while the machine is locked or the display is asleep. A
settings window covers all of it — General, Modules, Weather, About — reachable
from the menu bar, `⌘,`, or `islet settings`.

## Making it yours

Every module takes a colour, a size, and a position, edited against a **live
island preview** built from the real silhouette and the real compact views — so
what you tune is genuinely what you get.

```bash
islet settings --customize system.media
```

- **Colour** — the system palette or any custom colour.
- **Size** — scales that module's glyph and readout from 80% to 125%. The island
  keeps its own dimensions so it stays lined up with the camera.
- **Position** — *Automatic*, *Prefer front*, or *Prefer the small circle*, plus
  an ordering nudge. Placement is expressed as priority bias rather than a
  second layout pass: "prefer the small circle" *is* "rank below whatever else
  is live", and one ordering rule is far easier to reason about than two.

Deliberately a closed set. Arbitrary fonts and spacing would let anyone build
something that stops looking like the island; colour, size and placement cover
what people actually want without letting the design come apart.

Weather defaults to **on demand** rather than always-visible: a permanent
readout would mean the island is never idle, and "invisible until something
happens" is what makes it read as hardware rather than a widget stuck to the
bezel. One toggle in Settings changes that.

## The part nothing else has

Every other notch app shows you *its* features. Islet lets anything on your Mac
show *yours*.

```bash
# Wrap any command. Shows progress while it runs, then success or failure.
islet run --title "Deploying" --tint blue -- ./deploy.sh

# Or drive it manually.
id=$(islet start --title "Uploading" --indeterminate --tint blue)
islet update $id --progress 60%
islet end $id

# One-shot notifications.
islet flash --title "Tests passed" --icon symbol:checkmark.seal.fill --tint green

# A real timer that chimes at zero.
islet timer 25m --label Pomodoro

# Park build output on the island, then drag it straight into a message.
islet shelf out/*.png
```

Long `ffmpeg` renders, CI watches, `brew upgrade`, a training run, a deploy —
anything that takes long enough that you'd otherwise go check on it.

It's a Unix domain socket speaking newline-delimited JSON, at
`~/Library/Application Support/Islet/islet.sock`, `chmod 0600`. Nothing on the
network can reach it. `islet` is a thin client over it; you can just as easily
talk to it from Python, Node, or `nc`.

Shortcuts and Siri get native actions too: **Show Activity in Notch**, **Remove
Notch Activity**, **Clear the Notch**, **Start a Notch Timer**, and **Show
Weather in Notch**.

## Install

Requires macOS 14 Sonoma or newer, and Xcode's toolchain to build.

```bash
git clone <your-fork> Islet && cd Islet
make run
```

That compiles, assembles `Islet.app`, and launches it. To put the CLI on your
PATH:

```bash
make install-cli
```

It prints the `ln -s` command rather than running it, so you can read what you're
about to `sudo`.

## CLI reference

```
islet start        Post an ongoing activity. Prints its id.
islet flash        Post a transient activity that retires itself.
islet update <id>  Change an existing activity's content.
islet end <id>     Remove an activity.
islet end-all      Remove everything (optionally --source <name>).
islet list         Show what's currently on the island.
islet run -- <cmd> Run a command, showing progress; reports success or failure.
islet timer <dur>  Start a countdown that rings. 25m, 90s, 1h30m, or 25:00.
islet shelf [files] Park files on the island. No arguments clears it.
islet weather      Show current conditions on the island.
islet settings     Open Settings. --tab general|modules|weather|about
islet ping         Check that Islet.app is running.
```

Content flags: `--title --subtitle --body --trailing --icon --tint --progress
--indeterminate --progress-label --countdown --count-up --detail --open`

Behaviour flags: `--id --source --priority --dwell --stdin --json --quiet`

`--icon` takes `symbol:arrow.up.circle.fill`, `app:com.apple.Safari`, or
`file:/path/to.png`. `--tint` takes a colour name or `#RRGGBB`.

Full JSON payloads work too, for anything the flags don't cover:

```bash
echo '{"title":"Custom","progress":{"fraction":0.5}}' | islet start --stdin
```

Only `title` is required — you never have to write empty arrays.

## Icons

Islet draws its own — 37 marks on a single 24pt grid, in outline and solid
weights, with the weight chosen by the theme. SF Symbols are excellent, but they
carry Apple's optical conventions; at 20pt on black they read as system icons
borrowed onto someone else's surface.

Modules and the CLI still speak SF Symbol names, mapped onto the family, so
`islet start --icon symbol:bolt.fill` keeps working and anything unmapped falls
back to Apple's glyph rather than failing.

## Architecture

```
IsletCore      Model, scheduler, geometry, wire protocol. No AppKit, no SwiftUI.
IsletUI        The island: window, shape, morph, presentations.
IsletModules   The eleven system providers.
Islet          The app: menu bar, socket server, App Intents.
IsletCLI       The `islet` binary.
```

The rule that keeps it honest: **`ActivityStore` decides what is on screen, and
the views only decide how it looks.** Every visual is a function of one
`IslandComposition` value. Priority, preemption, and slot assignment live in one
readable method, so "why is the volume HUD covering my music" has one place to
look.

Providers degrade quietly. If an API is missing or a permission is declined, the
module reports `isAvailable == false` and disappears from the menu. Nothing is a
hard failure.

`IslandDesign` holds the visual vocabulary — spacing rhythm, type ramp, surface
and shadow specs, glyph glow, icon chips, button style. Presentations compose
from it rather than carrying their own point sizes, so the look stays coherent
as modules are added.

## Permissions

Three prompts, each from one module, each declinable without affecting anything else:

- **Automation** (Music/Spotify) — Now Playing.
- **Calendar** — the next-meeting module. Read-only.
- **Downloads folder** — download tracking.
- **Location** — weather, and only when you first ask for it. In on-demand mode nothing is requested until you use it, and you can type coordinates in by hand instead. They go to Open-Meteo and nowhere else.

And three you will never see:

- **No Accessibility access.** Caps Lock is read by polling `NSEvent.modifierFlags`, not by installing a global key monitor — asking to "control your computer" so we can draw an arrow would be a bad trade.
- **No microphone or camera access.** The privacy module asks the *hardware* whether someone else is using them; it never opens them.
- **No Full Disk Access.** Downloads are tracked through the partial files browsers leave in `~/Downloads`, not by reading Safari's container.

## Known gaps

- **Now Playing is Music and Spotify only.** The private MediaRemote framework that exposed system-wide Now Playing was locked behind an entitlement in macOS 15.4, so building on it would ship something that breaks. `MediaSource` is a protocol; an adapter can drop in when a supported path exists.
- **Brightness uses a private framework** (`DisplayServices`), loaded by name at runtime. There is no public API to read display brightness. If it ever vanishes, the module reports unavailable and everything else keeps working.
- **Ad-hoc signed.** Each rebuild changes the signature, so macOS may re-prompt for Automation access. Sign with a real identity to stop that.
- **No lock-screen presence, and there won't be.** Other notch apps advertise it; the macOS login window runs in a separate session and third-party processes cannot draw into it. Islet instead notices the lock and suspends every poll until you're back.
- **Downloads show bytes received, not a percentage.** A partial file says how much has landed but never how much is coming. A progress bar built on a guess would be worse than an honest indeterminate one.
- **Dragging *onto* the notch needs a real drag** — it could not be verified by script, only by hand. `islet shelf <files>` covers the same ground and is fully tested.

## Licence

MIT. See [LICENSE](LICENSE).
