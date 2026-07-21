# Security & Privacy

HashNotch is designed so you can verify every claim below by reading the
source. This page says exactly what the app reads, what it never does, and why.

## Everything stays on your Mac

No accounts. No analytics. No telemetry. No servers. HashNotch never uploads
anything, anywhere.

There is exactly **one** network request the app can ever make: while Spotify
is playing, it downloads the album artwork from Spotify's own image servers.
That request is HTTPS-only, restricted to Spotify's CDN hosts (`scdn.co`,
`spotifycdn.com`), and capped at 5 MB — any other URL is refused outright (see
`ArtworkPolicy` in `Sources/FeatureMedia/MediaRemoteReader.swift`, covered by
the automated checks). Nothing else in the app touches the network.

## What it reads, and why

| What | How | Why |
| --- | --- | --- |
| Network speed | Kernel per-interface byte counters (`getifaddrs`) | The up/down readout. It counts bytes only — it can never see what you send or receive. |
| Battery | IOKit power-source info | Level, charging state, time remaining. |
| Temperatures | Apple Silicon on-die sensors via the IOKit HID event system | The temperature readout. Read-only. |
| Now Playing | A short `/usr/bin/osascript` subprocess asks macOS and Spotify/Music for the current track and position | The media display. The play/pause/skip buttons send the matching command to Spotify or Music the same way — fixed commands only, nothing dynamic. Runs out of process so it can never crash the app, and is killed if it takes more than 10 seconds. |
| AI token usage | Local usage files: `~/.claude/projects/**/*.jsonl`, `~/.hashcortx/usage.jsonl`, and HashCerebrum's `usage.jsonl` | The tokens-today readout. Read-only; it adds up numbers and nothing more. |
| Live activities | `~/.hashnotch/activities.json`, written by your own scripts or Shortcuts | The activity strip. Treated as untrusted input: capped at 256 KB and 8 activities, text length-limited, progress clamped. |
| Mouse position | A global observe-only position monitor | So the island opens when you hover the notch. It never captures keystrokes. The overlay is fully click-through except while the panel is open — only then does the panel itself receive clicks (for the media buttons), and it turns click-through again the moment it closes. |

## Permissions it may ask for

- **Automation (control Spotify / Music)** — macOS shows this prompt the first
  time Now Playing asks Spotify or Music for the current track. Deny it and
  every other feature keeps working.

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
