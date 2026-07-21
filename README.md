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

`icon` is any SF Symbol name; `endsAt` (ISO 8601) drives a live countdown; expired
activities disappear on their own. Post one quickly:

```sh
./scripts/post-activity.sh "Food delivery" "Rider on the way" bicycle 12
./scripts/post-activity.sh --clear
```

## Now Playing

Whatever is playing (music, video) shows in the notch. Apple locked the direct
MediaRemote call behind an entitlement on macOS 15.4+/26, so HashNotch reads it
through a tiny `osascript` (JavaScript for Automation) subprocess using
`MRNowPlayingRequest` — which still works on those versions, and runs out of
process so it can never crash the app.

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

## License

[MIT](LICENSE) © 2026 Seif Hashish
