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
- **The panel's own controls sit beside the notch** — quit on its left, settings
  on its right — in the band of panel the hardware leaves showing. They are
  placed by the layout rather than floated over the first row, so no order you
  put the indicators in can collide with them.

### What it shows

- **Now Playing** — works with anything that plays: Spotify, Apple Music, TV,
  Podcasts, Anghami, VLC, a video in your browser, or an app nobody has written
  support for. macOS is asked directly for what is playing, so real artwork
  arrives for all of it without asking any app for anything. A scrolling title,
  audio bars, a progress bar you can **drag to move through the track**,
  play/pause/skip, and a system volume slider.
- **Swipe sideways across the open panel** to change track — left for the next,
  right for the previous, and only while something is actually playing.
- **Internet speed** — live upload and download.
- **Battery** — level, time remaining, and time to charge, with the adapter's
  wattage and whether that is a slow or fast charge. A Mac limited to 80%
  counts down to that level rather than to a full battery it will never reach.
  Charging is told apart from being *held* there. A heads-up when you plug in,
  unplug, reach full, or drop through 20% and 10%, and Low Power Mode in yellow
  with one click through to the setting that owns it.
- **AirPods** — charge remaining in each earbud and the case.
- **Temperatures** — real Apple Silicon on-die sensors, grouped into
  processor, graphics, drive, battery, and system.
- **AI token usage** — today's totals per tool, counted exactly the way
  HashMeterAi counts them. Only what your tools have written since the last
  count is read, so it stays cheap however often you ask for it; how often it
  counts is yours to set, from every minute down to only when you ask. The last
  count is remembered, so the panel opens on a number rather than on a zero it
  has not earned, with a line saying how old it is.
- **Timer** — any length you choose, counting
  down at the notch, with a chime and a notification at zero.
- **Processor load** — how busy the CPU is, as a number, a full-width graph of
  the last half-minute with a floor and ceiling to read it against, or both.
- **Memory** — how much of the Mac's memory is in use, the same figure Activity
  Monitor shows, with a matching graph. On Apple Silicon the processor and the
  graphics share one pool, so this is the whole machine.
- **Storage** — how full the startup disk is and how much room is left, with a
  bar underneath. The free figure is the one `df`, `diskutil` and Finder all
  report, so it can be checked against any of them.
- **Downloads** — a short notice when one finishes.
- **Live activities** — a local feed any app, script, or Shortcut can post to,
  with a built-in integration for Claude Code, HashCortX, and HashCerebrum.

### Built for the machine it runs on

- Native Swift (SwiftUI + AppKit), tuned for 120Hz ProMotion.
- Runs on **macOS 12 Monterey through macOS 26 Tahoe**, and asks each one for
  what it can comfortably give: the newest systems get the full treatment, and
  older ones get the same design with less to composite and a little longer to
  animate. Every version runs every feature, with one exception stated plainly
  where it appears — Open at Login needs macOS 13, and says so.
- Sampling stops entirely while the screen is asleep; timers are coalesced and
  monitors publish only when a displayed value actually changes.
- With the panel shut it costs nothing measurable: 0% processor and no idle
  wake-ups at all. Every reading that only appears inside the panel is taken
  only while the panel is open, and anything slow — the sensors, the AirPods
  report, the token count — runs off the thread that draws it.
- Every capability is a self-contained module — adding or removing one touches
  a single manifest line and never the core.

### Privacy

- No accounts, no analytics, no telemetry, no servers.
- The app writes no files; its only persistent state is its own settings, which
  now also hold the last token totals so the panel can open on a number.
- Switching an indicator off stops it reading, not just showing — a feature
  that is off is never started at all.
- **No network requests at all.** The artwork comes from macOS along with the
  title, so there is nothing to download. A download path remains for older
  macOS versions that do not answer that call — HTTPS-only, restricted to the
  image hosts, size-capped, and refused if a redirect would leave them.
- Reading what is playing sends no Apple Events, so it cannot raise an
  Automation prompt or stall behind one. Spotify and Music are asked only when
  you press a button on them, because once paused they release the system's
  media session and only their own scripting can resume them.
- The activity feed is treated as untrusted throughout, including the app a row
  may name: clicking one can only ever reach a real `.app` bundle installed
  where macOS keeps applications, with symlinks followed before the path is
  judged. A bundle dropped anywhere else is refused, so nothing that can write
  the feed can dress a stray app up as the window you were working in.
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
  [Install](README.md#-install).
