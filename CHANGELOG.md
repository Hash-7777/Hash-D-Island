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
  support for. macOS itself is asked what is playing, so the title, artist and
  position appear for all of it with no per-app support written for any of them.
  Album art comes from Spotify and Apple Music, and a video's thumbnail from
  your browser; anything else shows a placeholder tile. A scrolling title, audio
  bars, a progress bar you can **drag to move through the track**,
  play/pause/skip, and a system volume slider.
- **Swipe sideways across the open panel** to change track — left for the next,
  right for the previous, and only while something is actually playing.
- **Microphone** — the moment any app opens your microphone, a live dot and a
  running timer appear beside the notch with that app's own icon: FaceTime,
  Zoom, Teams, a browser call, a voice memo. macOS is asked one yes-or-no
  question — does this app have an input stream open — and the app **never
  listens, records or transcribes**. It holds no microphone permission of its
  own, and could not use one. On macOS 14.4 and later it can name the app;
  below that macOS offers only a device-wide answer, so the dot appears without
  a name attached.
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
- With the panel shut it costs nothing measurable: **0.13% of one core and no
  idle wake-ups at all**, measured over a minute against the packaged app with a
  track held on the strip. Every reading that only appears inside the panel is
  taken only while the panel is open, anything slow — the sensors, the AirPods
  report, the token count — runs off the thread that draws it, and a feature
  switched off is never started at all.
- Every capability is a self-contained module — adding or removing one touches
  a single manifest line and never the core.

### Privacy

- No accounts, no analytics, no telemetry, no servers.
- The app writes no files; its only persistent state is its own settings, which
  now also hold the last token totals so the panel can open on a number.
- Switching an indicator off stops it reading, not just showing — a feature
  that is off is never started at all.
- **One kind of network request, and only that one:** fetching a cover. HTTPS
  only, restricted to Spotify's and YouTube's image hosts, size-capped, and
  refused if a redirect would leave those hosts. It is fetched through an
  ephemeral session, so no artwork is written to disk. Nothing else in the app
  touches the network, and nothing about you is ever sent anywhere.
- Reading what is playing sends Apple Events, as the table in
  [SECURITY.md](SECURITY.md) sets out. Spotify and Music are asked for the
  track and its position; your browser is asked for the playing tab's address
  only when a web video needs a thumbnail, once per video rather than once per
  poll, and the tab list never leaves the helper subprocess. Deny any of it and
  everything else keeps working.
- **Nothing at all while your Mac is locked.** The island leaves the screen the
  moment you lock it and every indicator stops with it — not dimmed, not
  covered, gone, and reading nothing. What the notch shows is a summary of your
  afternoon, and a locked Mac is exactly when somebody who is not you might be
  standing in front of it.
- The activity feed is treated as untrusted throughout, including the app a row
  may name: clicking one can only ever reach a real `.app` bundle installed
  where macOS keeps applications, with symlinks followed before the path is
  judged. A bundle dropped anywhere else is refused, so nothing that can write
  the feed can dress a stray app up as the window you were working in.
- Everything it reads, every permission it can ask for, and both private Apple
  APIs it uses are listed in [SECURITY.md](SECURITY.md).

### Known limitations

- Hash D Island is measured to match a physical notch exactly. On a display
  without one — an external monitor, an iMac, an older Air — it is drawn against
  the top bezel and made exactly as tall as your menu bar, filling the band
  macOS never uses between the app menus and the status icons. Either way you
  can nudge its position and size per display in **Settings → Position**.
- Built for Apple Silicon (M1 and later). The temperature readout in particular
  is the real on-die sensors, which are an Apple Silicon interface.
- Because it reads system-wide Now Playing and the real temperature sensors, it
  uses Apple APIs the Mac App Store does not allow, so it is distributed
  directly and macOS asks you to confirm the first launch. See
  [Install](README.md#-install).
- The app is signed ad-hoc rather than with a Developer ID, and is not
  notarized, which is why that first launch takes the extra step.

### Licence

Released under the **[GNU General Public License v3](LICENSE)**. Free to use,
read, change and share; anything you distribute built on it stays free too.
