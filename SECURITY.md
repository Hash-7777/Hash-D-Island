# Security & Privacy

Hash D Island is designed so you can verify every claim below by reading the
source. This page says exactly what the app reads, what it never does, and why.

## Everything stays on your Mac

No accounts. No analytics. No telemetry. No servers. Hash D Island never uploads
anything, anywhere.

There is exactly **one** kind of network request the app can ever make, and on a
current macOS it does not make it at all: fetching the picture for what's
playing. macOS now hands the artwork over directly, along with the title, so
there is nothing to download — covers appear for every app, including ones this
app knows nothing about, without a single byte leaving the Mac.

The download path remains for the case where a macOS version does not answer
that call. If it is ever used, it is HTTPS-only, restricted to exactly the hosts
that serve those images (`scdn.co`, `spotifycdn.com`, `ytimg.com`), and capped
at 5 MB — any other URL, and any redirect that would leave those hosts, is
refused outright (see `ArtworkPolicy` in
`Sources/FeatureMedia/MediaRemoteReader.swift`, covered by the automated
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

## Removing it

Correspondingly short, and this is every trace:

1. Settings → turn **Open at Login** off, then **Quit Hash D Island**.
2. Drag the app from Applications to the Trash.
3. Delete `~/.hashdisland`.
4. `defaults delete com.hashdisland.app`

If you ran the Claude hook installer, also remove the two entries mentioning
`claude-code-hook.sh` from `~/.claude/settings.json` — a backup sits next to it.

No launch agents, no caches, no receipts. That is the complete list.

## What it reads, and why

| What | How | Why |
| --- | --- | --- |
| Network speed | Kernel per-interface byte counters (`getifaddrs`) | The up/down readout. It counts bytes only — it can never see what you send or receive. |
| Battery | IOKit power-source info, the connected adapter's own rating (`IOPSCopyExternalPowerAdapterDetails`), and the system's Low Power Mode flag (`ProcessInfo`) | Level, whether it is charging / held / full, time remaining or time to full, how many watts the adapter supplies, and whether Low Power Mode is on. All read-only. macOS offers no public way to *switch* Low Power Mode, so the panel's row opens System Settings at the Battery pane — unless you turn on "Switch Low Power Mode from the panel", which runs the one command that can and therefore asks macOS for an administrator password every time. |
| Temperatures | Apple Silicon on-die sensors via the IOKit HID event system | The temperature readout. Read-only. |
| AirPods battery | A short `/usr/sbin/system_profiler SPBluetoothDataType` subprocess — the same public report the System Information app shows you | The AirPods readout. That report lists every paired Bluetooth device; the app reads the battery percentages under the AirPods entry and discards the rest. Read-only, runs out of process so it can never wedge the app, and is killed if it takes more than 5 seconds. |
| Now Playing | macOS's own MediaRemote, asked **in process** for what is playing: title, artist, play state, position, and the artwork itself. No subprocess, and **no Apple Events — so reading a track asks no app for anything and can raise no permission prompt.** If a macOS version does not answer that call, it falls back to the older route below. A CoreAudio started/stopped signal and the players' own public play-state broadcasts wake the reader immediately | The media display, for **any** app that publishes a track — Spotify, Music, TV, Podcasts, a browser, or something nobody has heard of — all read identically. The play/pause/skip buttons send fixed commands: to Spotify/Music via their scripting (which is the only thing that reliably resumes them once paused), to anything else via the system's media channel, and to a browser by pressing the keyboard's media keys if you have allowed that. Dragging the progress bar asks the system to move the playhead. |
| Now Playing — **fallback only** | A short `/usr/bin/osascript` subprocess asking macOS and Spotify/Music for the current track, and for a web video reading your browser's open tab addresses and titles to find the one whose title matches, to derive its thumbnail (the tab list stays inside the subprocess — only the matching thumbnail URL comes back) | Reached only when the in-process call above is unavailable or has nothing, which on a current macOS is never. It is kept because these are private Apple APIs and this app supports several macOS versions. When it does run it behaves exactly as before: browsers asked once per video rather than once per poll, out of process so it can never crash the app, killed after 10 seconds. |
| **Microphone in use** | CoreAudio is asked one question per audio process: *is this process running an input stream?* The answer is a **boolean**. No audio is opened, no samples are read, and **the app holds no microphone permission** — reading this flag is not using the microphone, the way seeing a door is shut is not going through it | The live dot and the call timer. It shows that an app has your microphone open, which app it is, and for how long. It cannot know who you are speaking to, whether anyone is speaking, or what is said — **nothing is listened to, recorded or transcribed, ever**, and there is nothing here that could be extended to do so: the API returns a flag and a process id. The process id becomes a name and an icon through the list of running applications. Only real apps count, because macOS's own dictation service holds an input stream open permanently — and that filter is for *being an app*, not a list of meeting apps by name, so FaceTime, Zoom, Teams, Meet in a browser, a voice memo or a game all work without any of them being named anywhere. On macOS below 14.4 the per-process list does not exist, so the readout is simply unavailable rather than guessing. |
| System volume | CoreAudio, the public system-audio API | The panel's volume slider — read with each media poll, written only while you drag it. The same control your volume keys drive; no subprocess, no permission. |
| AI token usage | Local usage files: `~/.claude/projects/**/*.jsonl`, `~/.hashcortx/usage.jsonl`, and HashCerebrum's `usage.jsonl` | The tokens-today readout. Read-only; it adds up numbers and nothing more. Each file's read position is remembered within a run, so a count reads only what your tools have appended since the last one rather than re-reading the day's transcripts every time. How often it counts is yours to set in Settings, from every minute down to only when you ask; the last totals are kept in the app's own preferences so the panel can show a number immediately. |
| Processor load | The kernel's own tick counters (`host_statistics`) | The CPU readout. It reads how many ticks the machine spent busy versus idle — a total, with no notion of which programs were responsible. No permission, no subprocess. |
| Storage | The startup disk's capacity, from the public file-system API | The "74% full" readout and the bar under it. It asks how big the disk is and how much is free right now — the same figure `df` and `diskutil` report, so you can check it against either. It never lists, opens or looks inside a single file, and needs no permission. A breakdown by category is deliberately not attempted: every honest way to produce one is either a full walk of your disk or a permission prompt for folders this app has no other reason to open, so the row offers a link to macOS's own Storage settings instead. |
| Memory | The kernel's own virtual-memory counters (`host_statistics64`) and `hw.memsize` | The memory readout. It reads how many pages the machine has in use in total, with no notion of which programs are responsible. No permission, no subprocess. |
| Downloads | Lists the file names in your `~/Downloads` folder | The "download finished" notice. It reads names and dates only — it never opens, moves, or uploads a file — and shows the name of a file that just completed. |
| Live activities | `~/.hashdisland/activities.json`, written by your own scripts or Shortcuts | The activity strip. Treated as untrusted input: capped at 256 KB and 8 activities, text length-limited, progress clamped, a logo refused unless it is a readable image under 4 MB. An activity may also name an app to bring forward. That happens only when **you click the row**, and the app named is held to three rules: it must be a real `.app` bundle, it must live where macOS keeps applications (`/Applications`, `/System/Applications`, `/System/Library/CoreServices`, Apple's sealed cryptex volume that `/Applications/Safari.app` really points into, or `~/Applications`), and any symlink is followed before it is judged, so a link cannot stand in an allowed folder while pointing outside one. Clicking brings it forward if it is open and starts it if it is not — which is why a bundle dropped anywhere else is refused outright: this feed is writable by anything running as you, and without that rule a stray `/tmp/Update.app` could wear the words "your build finished". It can never run a loose executable, pass it an argument, or open a document. The optional Claude Code integration is a hook script YOU install (`scripts/install-claude-hooks.sh`, which backs up your Claude settings first); the hook writes only this feed file, and reads only which app it is running inside so that clicking can take you back to it. |
| Media keys | `CGEvent`, only with Accessibility granted and only when you have switched it on | So the panel's play, pause and skip buttons can drive a video in a browser. It SENDS three specific keys — play/pause, next, previous — and reads nothing at all. It never captures a keystroke, and with the setting off no key is ever sent. |
| Mouse position | Global observe-only monitors for position and scrolling | So the island opens when you hover the notch, and a two-finger swipe on the notch opens/closes the panel — scroll events are only ever acted on while the cursor is on the island. It never captures keystrokes. The overlay is fully click-through except while the panel is open — only then does the panel itself receive clicks (for the media buttons), and it turns click-through again the moment it closes. |

## Permissions it may ask for

- **Automation (control Spotify / Music)** — no longer asked in order to *read*
  anything: what is playing now comes from macOS itself. It is asked the first
  time you press play, pause or skip on a track owned by Spotify or Music,
  because once either is paused it releases the system's media session and only
  its own scripting can start it again. Deny it and everything except those two
  buttons for those two apps keeps working.
- **Automation (control your browser)** — on a current macOS, not asked at all:
  a web video's picture now comes from the system with everything else. It
  remains only on the fallback path described in the table, asked only if a web
  video is playing and nothing else already provided artwork. Hash D Island then reads your open
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

- **MediaRemote** — the only way to read system-wide Now Playing. Called in
  process for the track, the position and the artwork; the older `osascript`
  route remains only as a fallback for macOS versions that do not answer that
  call.
- **IOHIDEventSystemClient** — the only way to read the real Apple Silicon
  temperature sensors.

Everything else, including the microphone readout, uses documented public
interfaces. `kAudioHardwarePropertyProcessObjectList` is declared in Apple's
own `AudioHardware.h`.

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
