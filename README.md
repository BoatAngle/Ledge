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

Works on notchless Macs and external monitors too — it draws a virtual island of
the same dimensions.

**System modules**, all optional, all toggleable from the menu bar:

- **Now Playing** — Apple Music and Spotify, with album art, a live waveform, and transport controls
- **Battery & Charging** — announces plug-in, low-battery thresholds, and full charge
- **Sound & Output Device** — volume HUD, plus "your AirPods just connected"
- **Display Brightness** — brightness HUD
- **Focus** — the active Focus, persistently but quietly
- **Caps Lock** — a small confirmation
- **Camera & Microphone** — privacy indicators the moment something starts using them

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

# Countdowns tick locally — no need to send an update every second.
islet start --title "Pomodoro" --countdown 1500 --icon symbol:timer
```

Long `ffmpeg` renders, CI watches, `brew upgrade`, a training run, a deploy —
anything that takes long enough that you'd otherwise go check on it.

It's a Unix domain socket speaking newline-delimited JSON, at
`~/Library/Application Support/Islet/islet.sock`, `chmod 0600`. Nothing on the
network can reach it. `islet` is a thin client over it; you can just as easily
talk to it from Python, Node, or `nc`.

Shortcuts and Siri get native actions too: **Show Activity in Notch**, **Remove
Notch Activity**, and **Clear the Notch**.

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

## Architecture

```
IsletCore      Model, scheduler, geometry, wire protocol. No AppKit, no SwiftUI.
IsletUI        The island: window, shape, morph, presentations.
IsletModules   The seven system providers.
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

## Permissions

- **Automation** (Music/Spotify) — needed only by the Now Playing module, prompted on first use.
- **No Accessibility access.** Caps Lock is read by polling `NSEvent.modifierFlags`, not by installing a global key monitor — asking to "control your computer" so we can draw an arrow would be a bad trade.
- **No microphone or camera access.** The privacy module asks the *hardware* whether someone else is using them; it never opens them.

## Known gaps

- **Now Playing is Music and Spotify only.** The private MediaRemote framework that exposed system-wide Now Playing was locked behind an entitlement in macOS 15.4, so building on it would ship something that breaks. `MediaSource` is a protocol; an adapter can drop in when a supported path exists.
- **Brightness uses a private framework** (`DisplayServices`), loaded by name at runtime. There is no public API to read display brightness. If it ever vanishes, the module reports unavailable and everything else keeps working.
- **Ad-hoc signed.** Each rebuild changes the signature, so macOS may re-prompt for Automation access. Sign with a real identity to stop that.
- **Not yet built:** Calendar, timers, the AirDrop shelf, download tracking, and lock-screen presence. The engine and the activity model already support all of them — they're modules waiting to be written.

## Licence

MIT. See [LICENSE](LICENSE).
