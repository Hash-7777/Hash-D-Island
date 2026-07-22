# HashNotch

Your notch, finally alive.

HashNotch turns the dead space around the notch into a living, glanceable area —
like the iPhone's Dynamic Island, but built purely for Apple Silicon. It reacts
with smooth motion as things happen and keeps the numbers you care about one
glance away.

## What it shows

- **Live internet usage** — upload and download speed plus running totals
- **Battery** — level, charging state, health, and time remaining
- **Temperatures** — CPU, GPU, and other chip sensors
- **App interaction** — media controls and reactions to what's running
- **Motion** — expands, pulses, and animates as events happen

## Built for Apple Silicon

Native Swift (SwiftUI + AppKit), tuned for 120Hz ProMotion so every animation
stays buttery smooth with a light footprint. Runs entirely on your Mac — no
accounts, no cloud, no data collection.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac (M-series) with a notch display

## How it works

The notch stays a clean black shape at the top of your screen. **Hover it** and
it smoothly drops down into a rounded black panel — like the iPhone's Dynamic
Island — showing your internet speed, battery, temperatures, and AI token usage.
When something is live (a running activity), a slim strip appears below the notch
even without hovering. Because everything opens *below* the menu bar, it never
overlaps your menus or status icons.

## Live activities

Since macOS has no system API to read another app's live activity (that only
exists on iPhone), HashNotch instead reads a small local feed that any app,
script, or Apple Shortcut can write:

`~/.hashnotch/activities.json` — an array of:

```json
{ "id": "order-1", "icon": "bicycle", "title": "Food delivery",
  "subtitle": "Rider on the way", "progress": 0.6, "endsAt": "2026-07-21T21:30:00Z" }
```

`icon` is any SF Symbol name; `endsAt` (ISO 8601) drives a live countdown;
activities merge by `id` and expired ones disappear on their own. Post one
quickly:

```sh
./scripts/post-activity.sh "Food delivery" "Rider on the way" bicycle 12
./scripts/post-activity.sh --clear
```

## Claude Code in your notch

If you use Claude Code, one command wires it to the notch:

```sh
./scripts/install-claude-hooks.sh
```

From then on the island lights up the moment Claude **finishes a reply**
(checkmark + project name) or is **waiting for your permission** (raised hand
+ the reason) — so you can work in another window and glance at the notch
instead of the terminal. It uses Claude Code's own hook system; the hook is a
small script that writes only the local activities feed, and the installer
backs up your Claude settings before touching them.

## Now Playing

Whatever is playing (music, video) shows in the notch — artwork, a scrolling
title for long names, and audio bars that dance while sound is playing.
Spotify and Apple Music show their album art; a YouTube video playing in your
browser shows its video thumbnail. Open the panel and you get iPhone-style
media controls that work for all of it: play/pause, skip, a live progress
bar, and a system volume slider.

Apple locked the direct MediaRemote call behind an entitlement on macOS
15.4+/26, so HashNotch reads it through a tiny `osascript` (JavaScript for
Automation) subprocess using `MRNowPlayingRequest` — which still works on
those versions, and runs out of process so it can never crash the app.

## Customize it

HashNotch adds a small item to the menu bar. Click it for **HashNotch
Settings…**, where you can:

- turn each indicator on or off,
- choose how it looks (e.g. temperature as a number `52°`, a word `Cool`, or
  just a symbol), and
- turn on **Open at Login** so it comes back every time you start your Mac.

## Develop

The project is a Swift Package, so it builds and runs with the Command Line
Tools alone — no full Xcode required to try it.

```sh
swift build               # compile everything
swift run HashNotch       # launch the notch overlay + menu-bar item
swift run HashNotchChecks # run the core checks
./scripts/build_app.sh    # assemble build/HashNotch.app (needed for login item)
```

"Open at Login" only works from the built `.app` (macOS manages login items by
bundle), so run `build_app.sh` and launch `build/HashNotch.app` to use it.

Every capability is a self-contained module. Adding or removing one touches a
single manifest line and never the core — see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Privacy & security

Everything runs and stays on your Mac — no accounts, no analytics, no servers.
The only network request HashNotch can ever make is fetching album artwork
from Spotify's own image server while Spotify is playing. Exactly what the app
reads, why, and the one permission it may ask for are spelled out in
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 Seif Hashish
