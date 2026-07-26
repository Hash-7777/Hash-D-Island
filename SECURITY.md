# Security & Privacy

Hash D Island is designed so you can verify every claim below by reading the
source. This page says exactly what the app reads, what it never does, and why.

## Everything stays on your Mac

No accounts. No analytics. No telemetry. No servers. Hash D Island never uploads
anything, anywhere.

There is exactly **one** kind of network request the app can ever make:
fetching the picture for what's playing — album art from Spotify's own image
servers, or a web video's thumbnail from YouTube's thumbnail server. Those
requests are HTTPS-only, restricted to exactly those hosts (`scdn.co`,
`spotifycdn.com`, `ytimg.com`), and capped at 5 MB — any other URL, and any
redirect that would leave those hosts, is refused outright (see `ArtworkPolicy`
in `Sources/FeatureMedia/MediaRemoteReader.swift`, covered by the automated
checks). The fetch uses an ephemeral session, so no artwork is ever written to
disk. Nothing else in the app touches the network.

## What it writes

Almost nothing. The app itself writes **no files at all** — its only persistent
state is its own settings, stored where every Mac app stores them
(`~/Library/Preferences/com.hashdisland.app.plist`). Alongside your choices,
that holds one small piece of remembered state: the last AI token totals and the
day they belong to, so the panel opens on a number rather than on a zero it has
not earned. It is four integers and a date, and a set from any day but today is
discarded rather than shown. It never writes to the files it reads, and artwork
is fetched through an ephemeral session so not even an image cache lands on disk.

The one folder that carries Hash D Island's name, `~/.hashdisland`, is written by
*you* — by the optional helper scripts in `scripts/`, or by anything else you
choose to post activities with. The app only ever reads it.

Removing Hash D Island is correspondingly short, and the README's
[Remove it](README.md#remove-it) section lists every trace.

## What it reads, and why

| What | How | Why |
| --- | --- | --- |
| Network speed | Kernel per-interface byte counters (`getifaddrs`) | The up/down readout. It counts bytes only — it can never see what you send or receive. |
| Battery | IOKit power-source info, the connected adapter's own rating (`IOPSCopyExternalPowerAdapterDetails`), and the system's Low Power Mode flag (`ProcessInfo`) | Level, whether it is charging / held / full, time remaining or time to full, how many watts the adapter supplies, and whether Low Power Mode is on. All read-only. macOS offers no public way to *switch* Low Power Mode, so the panel's row opens System Settings at the Battery pane — unless you turn on "Switch Low Power Mode from the panel", which runs the one command that can and therefore asks macOS for an administrator password every time. |
| Temperatures | Apple Silicon on-die sensors via the IOKit HID event system | The temperature readout. Read-only. |
| AirPods battery | A short `/usr/sbin/system_profiler SPBluetoothDataType` subprocess — the same public report the System Information app shows you | The AirPods readout. That report lists every paired Bluetooth device; the app reads the battery percentages under the AirPods entry and discards the rest. Read-only, runs out of process so it can never wedge the app, and is killed if it takes more than 5 seconds. |
| Now Playing | A short `/usr/bin/osascript` subprocess asks macOS and Spotify/Music for the current track and position; for a web video it reads your browser's open tab addresses and titles to find the one whose title matches what's playing, and derives that video's thumbnail (the tab list stays inside the subprocess — only the matching thumbnail URL comes back). Browsers are asked **once per video**, not once per poll: the answer is remembered whether or not a thumbnail was found, and only re-asked when the track changes. A CoreAudio started/stopped signal and the players' own public play-state broadcasts wake the reader immediately | The media display. The play/pause/skip buttons send fixed commands — to Spotify/Music via their scripting, to anything else via the system's media channel, and to a browser by pressing the keyboard's media keys if you have allowed that. Runs out of process so it can never crash the app, and is killed if it takes more than 10 seconds. |
| System volume | CoreAudio, the public system-audio API | The panel's volume slider — read with each media poll, written only while you drag it. The same control your volume keys drive; no subprocess, no permission. |
| AI token usage | Local usage files: `~/.claude/projects/**/*.jsonl`, `~/.hashcortx/usage.jsonl`, and HashCerebrum's `usage.jsonl` | The tokens-today readout. Read-only; it adds up numbers and nothing more. Each file's read position is remembered within a run, so a count reads only what your tools have appended since the last one rather than re-reading the day's transcripts every time. How often it counts is yours to set in Settings, from every minute down to only when you ask; the last totals are kept in the app's own preferences so the panel can show a number immediately. |
| Processor load | The kernel's own tick counters (`host_statistics`) | The CPU readout. It reads how many ticks the machine spent busy versus idle — a total, with no notion of which programs were responsible. No permission, no subprocess. |
| Storage | The startup disk's capacity, from the public file-system API | The "63% full" readout and the bar under it. It asks how big the disk is and how much room is left — twice, because macOS reports free space both with and without the caches it is willing to purge, and the gap between those two answers is what the "reclaimable" figure names. It never lists, opens or looks inside a single file, and needs no permission. A breakdown by category is deliberately not attempted: every honest way to produce one is either a full walk of your disk or a permission prompt for folders this app has no other reason to open, so the row offers a link to macOS's own Storage settings instead. |
| Memory | The kernel's own virtual-memory counters (`host_statistics64`) and `hw.memsize` | The memory readout. It reads how many pages the machine has in use in total, with no notion of which programs are responsible. No permission, no subprocess. |
| Downloads | Lists the file names in your `~/Downloads` folder | The "download finished" notice. It reads names and dates only — it never opens, moves, or uploads a file — and shows the name of a file that just completed. |
| Live activities | `~/.hashdisland/activities.json`, written by your own scripts or Shortcuts | The activity strip. Treated as untrusted input: capped at 256 KB and 8 activities, text length-limited, progress clamped, a logo refused unless it is a readable image under 4 MB. An activity may also name an app to bring forward. That happens only when **you click the row**, and the app named is held to three rules: it must be a real `.app` bundle, it must live where macOS keeps applications (`/Applications`, `/System/Applications`, `/System/Library/CoreServices`, or `~/Applications`), and any symlink is followed before it is judged, so a link cannot stand in an allowed folder while pointing outside one. Clicking brings it forward if it is open and starts it if it is not — which is why a bundle dropped anywhere else is refused outright: this feed is writable by anything running as you, and without that rule a stray `/tmp/Update.app` could wear the words "your build finished". It can never run a loose executable, pass it an argument, or open a document. The optional Claude Code integration is a hook script YOU install (`scripts/install-claude-hooks.sh`, which backs up your Claude settings first); the hook writes only this feed file, and reads only which app it is running inside so that clicking can take you back to it. |
| Media keys | `CGEvent`, only with Accessibility granted and only when you have switched it on | So the panel's play, pause and skip buttons can drive a video in a browser. It SENDS three specific keys — play/pause, next, previous — and reads nothing at all. It never captures a keystroke, and with the setting off no key is ever sent. |
| Mouse position | Global observe-only monitors for position and scrolling | So the island opens when you hover the notch, and a two-finger swipe on the notch opens/closes the panel — scroll events are only ever acted on while the cursor is on the island. It never captures keystrokes. The overlay is fully click-through except while the panel is open — only then does the panel itself receive clicks (for the media buttons), and it turns click-through again the moment it closes. |

## Permissions it may ask for

- **Automation (control Spotify / Music)** — macOS shows this prompt the first
  time Now Playing asks Spotify or Music for the current track. Deny it and
  every other feature keeps working.
- **Automation (control your browser)** — asked only if a web video is playing
  and nothing else already provided artwork. Hash D Island then reads your open
  browser tabs' addresses and titles to find the one whose title matches what's
  playing, and derives only that video's thumbnail. This happens once per
  video, not continuously: the result is remembered — including "no thumbnail
  for this one" — so a track that has no web thumbnail does not cause a repeat
  scan. The tab list never leaves the helper subprocess: only the single
  matching thumbnail URL is returned to the app, and only its image (from
  YouTube's thumbnail host) is fetched. Deny this and Now Playing simply shows
  a placeholder tile instead.
- **Your Downloads folder** — macOS protects it, so the first time the download
  notice looks there, macOS asks. Deny it and every other feature keeps
  working; you simply get no "download finished" notice.
- **Notifications** — asked the first time you start the timer, so it can post
  a banner when the timer ends. Deny it and the timer still chimes and shows
  "Time's up" in the notch.

- **Accessibility** — asked **only if you turn on "Control video in your
  browser"**, and never otherwise. It is off by default. macOS gates pressing
  the keyboard's media keys behind this permission, and pressing them is the
  only way to reach a video playing in a browser: the system's media channel
  accepts play and pause commands for one and does nothing with them (measured
  — pause returns success, the video keeps playing). With this off, the media
  buttons still work for Spotify and Apple Music, which have scripting
  interfaces of their own.

That is the complete list. Hash D Island never asks for Input Monitoring,
Screen Recording, or Full Disk Access, and asks for Accessibility only if you
switch on the one setting above.

## Off means off

Every row in the table above belongs to a feature you can switch off in
**Settings → Indicators**, and switching one off **stops the work, not just the
display**. A feature that is off is never started: it opens no files, runs no
subprocess, and can trigger none of the permission prompts above. Turn
Downloads off and the folder is never listed; turn Now Playing off and your
media apps and browsers are never asked anything.

The same holds while your screen is asleep — all sampling stops until it wakes
— and a feature you switched off does not quietly come back on wake. This is
covered by the automated checks (`FeatureRegistry.syncRunning`).

## Private APIs, stated openly

Two features use non-public Apple APIs, both read-only:

- **MediaRemote** (via the osascript subprocess) — the only way to read
  system-wide Now Playing on macOS 15.4+ since Apple locked the direct call
  behind an entitlement.
- **IOHIDEventSystemClient** — the only way to read the real Apple Silicon
  temperature sensors.

If Apple changes either, those readouts degrade to a placeholder and the rest
of the app keeps working. Because of these APIs, Hash D Island is distributed
directly rather than through the Mac App Store.

## Verify it yourself

The whole app builds from source with the Command Line Tools alone:

```sh
swift build
swift run HashDIslandChecks   # the automated checks, including the policies above
```

All commits on this repository are SSH-signed.

## Reporting a vulnerability

If you find a security issue, please open a private security advisory on this
repository's GitHub page (Security → Advisories → Report a vulnerability), or
open an issue if it is not sensitive. Reports are welcome and taken seriously.
