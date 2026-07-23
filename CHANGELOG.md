# Changelog

All notable changes to Hash D Island are recorded here.

## 1.0.0 — first release

The notch becomes a living surface: quiet when nothing is happening, alive the
moment something is.

### Around the notch

- **At rest** the island matches the physical notch exactly, so the app is
  invisible until it has something to say.
- **A live strip** appears beside the notch — no hover needed — whenever
  something is happening: music playing, a timer counting down, a download
  landing, an activity running. A track keeps its place while paused, so the
  artwork and the resume button stay where you left them.
- **Hover, or swipe down with two fingers,** to drop the full panel below the
  menu bar. Because it opens below the menu bar, it never covers your menus or
  status icons.

### What it shows

- **Now Playing** — artwork, a scrolling title, audio bars, a live progress
  bar, play/pause/skip, and a system volume slider. Works with Spotify, Apple
  Music, and anything else through the system media channel, including video in
  your browser (with the video's thumbnail as artwork).
- **Internet speed** — live upload and download.
- **Battery** — level, time remaining or time to full, and a heads-up when you
  plug in, unplug, reach full, or drop through 20% and 10%. Charging is told
  apart from *held at 80% for battery health*, and Low Power Mode shows in
  yellow with one click through to the setting that owns it.
- **AirPods** — charge remaining in each earbud and the case.
- **Temperatures** — real Apple Silicon on-die sensors, grouped into
  processor, graphics, storage, battery, and system.
- **AI token usage** — today's totals per tool, counted exactly the way
  HashMeterAi counts them.
- **Timer** — quick 5/15/25 minute starts or any length you choose, counting
  down at the notch, with a chime and a notification at zero.
- **Downloads** — a short notice when one finishes.
- **Live activities** — a local feed any app, script, or Shortcut can post to,
  with a built-in integration for Claude Code, HashCortX, and HashCerebrum.

### Built for the machine it runs on

- Native Swift (SwiftUI + AppKit), tuned for 120Hz ProMotion.
- Sampling stops entirely while the screen is asleep; timers are coalesced and
  monitors publish only when a displayed value actually changes.
- Every capability is a self-contained module — adding or removing one touches
  a single manifest line and never the core.

### Privacy

- No accounts, no analytics, no telemetry, no servers.
- The app writes no files; its only persistent state is its own settings.
- Switching an indicator off stops it reading, not just showing — a feature
  that is off is never started at all.
- One kind of network request exists at all — fetching album or video artwork —
  restricted to Spotify's and YouTube's image hosts over HTTPS, size-capped,
  and refused if a redirect would leave those hosts.
- Everything it reads, every permission it can ask for, and both private Apple
  APIs it uses are listed in [SECURITY.md](SECURITY.md).

### Known limitations

- Hash D Island is built for Macs with a notch, where the island is measured to
  match the hardware exactly. A display without one — an external monitor, an
  iMac, an older Air — gets a small pill hanging just below the menu bar
  instead; everything works, but it is not the shape the app was drawn for.
  Either way you can nudge its position and size per display in
  **Settings → Position**.
- Because it reads system-wide Now Playing and the real temperature sensors, it
  uses Apple APIs the Mac App Store does not allow, so it is distributed
  directly and macOS asks you to confirm the first launch. See
  [Download & install](README.md#download--install).
