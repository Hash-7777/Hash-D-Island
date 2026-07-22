# Security & Privacy

HashNotch is designed so you can verify every claim below by reading the
source. This page says exactly what the app reads, what it never does, and why.

## Everything stays on your Mac

No accounts. No analytics. No telemetry. No servers. HashNotch never uploads
anything, anywhere.

There is exactly **one** kind of network request the app can ever make:
fetching the picture for what's playing — album art from Spotify's own image
servers, or a web video's thumbnail from YouTube's thumbnail server. Those
requests are HTTPS-only, restricted to exactly those hosts (`scdn.co`,
`spotifycdn.com`, `ytimg.com`), and capped at 5 MB — any other URL is refused
outright (see `ArtworkPolicy` in
`Sources/FeatureMedia/MediaRemoteReader.swift`, covered by the automated
checks). Nothing else in the app touches the network.

## What it reads, and why

| What | How | Why |
| --- | --- | --- |
| Network speed | Kernel per-interface byte counters (`getifaddrs`) | The up/down readout. It counts bytes only — it can never see what you send or receive. |
| Battery | IOKit power-source info | Level, charging state, time remaining. |
| Temperatures | Apple Silicon on-die sensors via the IOKit HID event system | The temperature readout. Read-only. |
| Now Playing | A short `/usr/bin/osascript` subprocess asks macOS and Spotify/Music for the current track and position; for a web video it asks your browser only for the playing tab's address, to derive the thumbnail. A CoreAudio started/stopped signal and the players' own public play-state broadcasts wake the reader immediately | The media display. The play/pause/skip buttons send fixed commands — to Spotify/Music via their scripting, to anything else via the system's media-key channel. Runs out of process so it can never crash the app, and is killed if it takes more than 10 seconds. |
| System volume | CoreAudio, the public system-audio API | The panel's volume slider — read with each media poll, written only while you drag it. The same control your volume keys drive; no subprocess, no permission. |
| AI token usage | Local usage files: `~/.claude/projects/**/*.jsonl`, `~/.hashcortx/usage.jsonl`, and HashCerebrum's `usage.jsonl` | The tokens-today readout. Read-only; it adds up numbers and nothing more. |
| Downloads | Lists the file names in your `~/Downloads` folder | The "download finished" notice. It reads names and dates only — it never opens, moves, or uploads a file — and shows the name of a file that just completed. |
| Live activities | `~/.hashnotch/activities.json`, written by your own scripts or Shortcuts | The activity strip. Treated as untrusted input: capped at 256 KB and 8 activities, text length-limited, progress clamped. The optional Claude Code integration is a hook script YOU install (`scripts/install-claude-hooks.sh`, which backs up your Claude settings first); the hook writes only this feed file and reads nothing. |
| Mouse position | Global observe-only monitors for position and scrolling | So the island opens when you hover the notch, and a two-finger swipe on the notch opens/closes the panel — scroll events are only ever acted on while the cursor is on the island. It never captures keystrokes. The overlay is fully click-through except while the panel is open — only then does the panel itself receive clicks (for the media buttons), and it turns click-through again the moment it closes. |

## Permissions it may ask for

- **Automation (control Spotify / Music)** — macOS shows this prompt the first
  time Now Playing asks Spotify or Music for the current track. Deny it and
  every other feature keeps working.
- **Automation (control your browser)** — asked only if a web video is playing
  and only to read the playing tab's address so the video's thumbnail can be
  shown. Deny it and Now Playing simply shows a placeholder tile instead.

That is the complete list. HashNotch never asks for Accessibility, Input
Monitoring, Screen Recording, or Full Disk Access.

## Private APIs, stated openly

Two features use non-public Apple APIs, both read-only:

- **MediaRemote** (via the osascript subprocess) — the only way to read
  system-wide Now Playing on macOS 15.4+ since Apple locked the direct call
  behind an entitlement.
- **IOHIDEventSystemClient** — the only way to read the real Apple Silicon
  temperature sensors.

If Apple changes either, those readouts degrade to a placeholder and the rest
of the app keeps working. Because of these APIs, HashNotch is distributed
directly rather than through the Mac App Store.

## Verify it yourself

The whole app builds from source with the Command Line Tools alone:

```sh
swift build
swift run HashNotchChecks   # the automated checks, including the policies above
```

All commits on this repository are SSH-signed.

## Reporting a vulnerability

If you find a security issue, please open a private security advisory on this
repository's GitHub page (Security → Advisories → Report a vulnerability), or
open an issue if it is not sensitive. Reports are welcome and taken seriously.
