# HashNotch

Your notch, finally alive.

HashNotch turns the dead space around the notch into a living, glanceable area —
like the iPhone's Dynamic Island, but built purely for Apple Silicon. It reacts
with smooth motion as things happen and keeps the numbers you care about one
glance away.

## See it in action

<p align="center">
  <img src="docs/media/hero.png" width="300"
       alt="The HashNotch panel dropped below the notch — Now Playing, today's AI tokens, internet speed, temperatures, and a timer">
</p>

<p align="center">
  <img src="docs/media/live.png" width="360"
       alt="The live strip beside the notch — album art, the track title, and audio bars that dance while it plays">
</p>

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

## Download & install

1. Get `HashNotch.app` from the
   [Releases](https://github.com/Hash-7777/Hash_Mac_Notch/releases) page, unzip
   it, and drag **HashNotch** into your **Applications** folder. (Or build it
   yourself — see [Develop](#develop) below.)
2. **The first time you open it,** macOS says it can't verify the developer.
   Click **Done**, then open **System Settings → Privacy & Security**, scroll to
   the bottom, and click **Open Anyway** next to HashNotch. Confirm once and it
   launches; every time after that it opens normally. (On older macOS you can
   instead right-click the app and choose **Open**.)
3. HashNotch has no Dock icon — it lives around the notch and in the menu bar.
   Click the **gear** in its panel for **HashNotch Settings…** to choose what
   shows and to turn on **Open at Login**.

> **Why the extra step to open it?** HashNotch reads system-wide Now Playing and
> the real Apple Silicon temperature sensors, which need Apple APIs the Mac App
> Store doesn't allow — so it ships straight from here instead of the store, and
> macOS asks you to confirm the first launch. It makes no network connection
> except to load album and video artwork, collects nothing, and every commit is
> signed. Exactly what it reads and why is spelled out in [SECURITY.md](SECURITY.md).

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

## Your AI usage

HashNotch keeps today's AI token use one glance away. The strip shows a running
total across your tools; open the panel for the per-tool breakdown — Claude
Code, HashCortX, and HashCerebrum — under a **HashMeterAi** heading, counted the
same way [HashMeterAi](https://github.com/Hash-7777/HashMeterAi) counts them so
the two always agree. It reads only the local usage files those tools already
write (`~/.claude/projects/**/*.jsonl`, `~/.hashcortx/usage.jsonl`, and
HashCerebrum's usage log) — read-only, on your Mac, adding up numbers and
nothing more.

## When your AI tools finish

Work in another window and let the notch tell you the moment an AI tool is done
— a checkmark landing on the notch, like the iPhone Dynamic Island.

- **Claude Code** — one command wires it up:

  ```sh
  ./scripts/install-claude-hooks.sh
  ```

  From then on the island lights up the moment Claude **finishes a reply**
  (checkmark + project name) or is **waiting for your permission** (raised hand
  + the reason). It uses Claude Code's own hook system; the hook is a small
  script that writes only the local activities feed, and the installer backs up
  your Claude settings before touching them.

- **HashCortX** and **HashCerebrum** — built in, nothing to install. HashCortX
  flashes "HashCortX finished" when a run completes; HashCerebrum lights up when
  a manuscript or peer review is ready.

Under the hood they all use the same local feed
(`~/.hashnotch/activities.json`, see [Live activities](#live-activities)), so
any app, script, or Shortcut can light up your notch the same way.

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
