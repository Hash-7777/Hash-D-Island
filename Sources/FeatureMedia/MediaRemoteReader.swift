import Foundation

/// Which app owns the current track — controls only exist for apps we can
/// script (Spotify and Music); everything else is display-only.
public enum MediaSource: String {
    case spotify
    case music
    case other
}

/// A playback command the user can send from the panel.
///
/// Play and pause are deliberately separate rather than one toggle. A toggle
/// obeys whoever it reaches, which is wrong twice over: if our idea of the play
/// state has drifted it does the opposite of what the button showed, and the
/// system media channel accepts a toggle for a player that has already released
/// the now-playing session, reports success, and changes nothing — which is
/// exactly how a paused track ends up refusing to resume.
public enum MediaCommand {
    case play
    case pause
    case next
    case previous

    /// The verb a scriptable player (Spotify, Music) understands.
    public var scriptVerb: String {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        case .next: return "next track"
        case .previous: return "previous track"
        }
    }

    /// The system media-channel code: kMRPlay = 0, kMRPause = 1,
    /// kMRNextTrack = 4, kMRPreviousTrack = 5. Note the absence of 2,
    /// kMRTogglePlayPause — see the type's note above.
    public var remoteCode: Int {
        switch self {
        case .play: return 0
        case .pause: return 1
        case .next: return 4
        case .previous: return 5
        }
    }
}

/// The current track/video playing anywhere on the Mac.
public struct NowPlaying {
    /// Package-visible so the checks can build one, which is what lets the
    /// polling rules be pinned without a player running.
    package init(
        title: String, artist: String?, isPlaying: Bool, artwork: Data?,
        source: MediaSource, elapsed: Double?, duration: Double?, fetchedAt: Date
    ) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.artwork = artwork
        self.source = source
        self.elapsed = elapsed
        self.duration = duration
        self.fetchedAt = fetchedAt
    }

    public let title: String
    public let artist: String?
    public let isPlaying: Bool
    public let artwork: Data?
    public let source: MediaSource
    public let elapsed: Double?
    public let duration: Double?
    public let fetchedAt: Date
}

extension NowPlaying: Equatable {
    /// `elapsed`/`fetchedAt` advance on every poll; excluding them means a
    /// steadily playing track publishes no UI churn. Progress is delivered
    /// separately by the monitor.
    public static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.isPlaying == rhs.isPlaying
            && lhs.artwork == rhs.artwork
            && lhs.source == rhs.source
            && Int(lhs.duration ?? -1) == Int(rhs.duration ?? -1)
    }
}

/// Decides which artwork URLs the app is willing to download. Spotify's
/// scripting interface hands us a URL string; we only ever fetch it when it is
/// HTTPS and points at Spotify's own image CDN — never an arbitrary host, never
/// a non-HTTPS scheme (a `file://` or `http://` URL is refused outright). This
/// is the app's only network access, so the policy is deliberately narrow and
/// covered by HashDIslandChecks.
package enum ArtworkPolicy {
    /// Hosts artwork may come from: Spotify's album-art CDNs and YouTube's
    /// thumbnail server (for web videos).
    private static let trustedSuffixes = ["scdn.co", "spotifycdn.com", "ytimg.com"]

    package static func isTrustedURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else { return false }
        return trustedSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Album art is ~100 KB; refuse anything absurdly larger.
    package static let maxArtworkBytes = 5_000_000
}

/// Reads system-wide "Now Playing" on all macOS versions — including 15.4+/26,
/// where Apple locked the direct MediaRemote call behind an entitlement.
///
/// Universal title / artist / play-state come from `MRNowPlayingRequest` via a
/// short `osascript` subprocess (works on 26, and can't crash us). Artwork is
/// null through that path on 15.4+, so it is pulled straight from Spotify
/// (`artwork url`, downloaded) or Apple Music (raw data) when they're the
/// player. Browsers/other apps get no art (a tasteful placeholder is shown).
///
/// The script is passed inline via `-e` — nothing is written to disk, so there
/// is no temp file another process could swap out between write and execute.
final class MediaRemoteReader {
    private let queue = DispatchQueue(label: "com.hashdisland.media.nowplaying")
    /// Commands run on their own queue so a click NEVER waits behind an
    /// in-flight fetch — play/pause must feel instant.
    private let commandQueue = DispatchQueue(label: "com.hashdisland.media.commands", qos: .userInitiated)
    /// Downloading a cover is the one slow thing here, and it is never the
    /// thing the reader was asked for. It gets its own queue so the track can
    /// be published the moment the script returns.
    private let artworkQueue = DispatchQueue(label: "com.hashdisland.media.artwork", qos: .utility)

    private let stateLock = NSLock()
    private var inFlight = false

    /// Called when a cover finishes downloading, with the title it belongs to,
    /// on a background queue. The title comes back with it because by then the
    /// track may already have changed, and artwork for the previous song is
    /// worse than none.
    var onArtwork: ((String, Data) -> Void)?

    private var cachedArtworkURL: String?
    private var cachedArtwork: Data?
    /// The track the held artwork belongs to. Artwork is fetched once when a
    /// track starts and then left alone until the track changes — the cover of
    /// a song does not change while the song is playing.
    private var artworkTitle: String?
    /// The cover URL currently being downloaded, so a poll landing mid-download
    /// does not start the same fetch again.
    private var pendingArtworkURL: String?

    private static let osascript = "/usr/bin/osascript"

    /// How long one osascript round-trip may take before we kill it (it can
    /// stall indefinitely behind a macOS Automation permission dialog).
    private static let fetchTimeout: TimeInterval = 10

    private static let script = """
    function run(argv) {
      ObjC.import('Foundation');
      let title = null, artist = null, playing = false, artworkUrl = null, artwork = null;
      let source = 'other', elapsed = null, duration = null;

      // What the app already holds. Artwork is expensive to produce — Apple
      // Music base64-encodes the whole image, Spotify costs an Apple Event —
      // and a track's cover does not change while the track does not. So when
      // the caller says it already has the art for this exact title, none of
      // that work is done at all and `artUnchanged` says so.
      const knownArtTitle = argv.length >= 3 ? argv[2] : '';
      const haveArt = argv.length >= 4 && argv[3] === '1';
      let artUnchanged = false;
      function artIsCurrent(name) {
        return haveArt && knownArtTitle !== '' && knownArtTitle === name;
      }

      const bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
      bundle.load;
      const cls = $.NSClassFromString('MRNowPlayingRequest');
      if (cls) {
        const item = cls.localNowPlayingItem;
        if (item && !item.isNil()) {
          const info = item.nowPlayingInfo;
          if (info && !info.isNil()) {
            function s(k) { const v = info.objectForKey(k); return (v && !v.isNil()) ? ObjC.unwrap(v) : null; }
            title = s('kMRMediaRemoteNowPlayingInfoTitle');
            artist = s('kMRMediaRemoteNowPlayingInfoArtist');
            const rate = s('kMRMediaRemoteNowPlayingInfoPlaybackRate');
            playing = rate ? (rate > 0) : false;
            elapsed = s('kMRMediaRemoteNowPlayingInfoElapsedTime');
            duration = s('kMRMediaRemoteNowPlayingInfoDuration');
          }
        }
      }

      // A playing Spotify/Music always claims the slot (artwork, position,
      // controls). A PAUSED one claims it only when nothing else is playing,
      // so the panel can keep showing the track with a resume button.
      try {
        const sp = Application('Spotify');
        if (sp.running()) {
          const st = String(sp.playerState());
          if (st === 'playing' || st === 'paused') {
            const spName = sp.currentTrack.name();
            // Claim the slot when Spotify is playing, OR when it is paused and it
            // is what's showing (nothing else is playing, or it's the same
            // track). Claiming a PAUSED track keeps its artwork and lets the
            // resume go through Spotify's own scripting instead of the generic
            // media channel — so the play button actually resumes it.
            if (st === 'playing' || !title || title === spName) {
              source = 'spotify';
              if (artIsCurrent(spName)) {
                artUnchanged = true;
              } else {
                artworkUrl = sp.currentTrack.artworkUrl();
              }
              elapsed = sp.playerPosition();
              duration = sp.currentTrack.duration() / 1000;
              title = spName;
              artist = sp.currentTrack.artist();
              playing = (st === 'playing');
            }
          }
        }
      } catch (e) {}

      try {
        const mu = Application('Music');
        if (source === 'other' && mu.running()) {
          const st = String(mu.playerState());
          if (st === 'playing' || st === 'paused') {
            const muName = mu.currentTrack.name();
            // Same rule as Spotify: a paused Music track keeps its slot (and its
            // artwork + scripting control) when it's what's showing.
            if (st === 'playing' || !title || title === muName) {
              source = 'music';
              elapsed = mu.playerPosition();
              duration = mu.currentTrack.duration();
              title = muName;
              artist = mu.currentTrack.artist();
              playing = (st === 'playing');
              if (artIsCurrent(muName)) {
                artUnchanged = true;
              } else {
                const arts = mu.currentTrack.artworks;
                if (arts.length > 0) {
                  const raw = arts[0].rawData();
                  artwork = $.NSString.alloc.initWithDataEncoding(raw.base64EncodedDataWithOptions(0), $.NSUTF8StringEncoding).js;
                }
              }
            }
          }
        }
      } catch (e) {}

      // Web video (YouTube in a browser): find the playing tab's address and
      // derive the video thumbnail. Only runs when nothing else provided
      // artwork, and only when this title has not been looked up already —
      // argv carries the previous title and what the lookup produced for it,
      // which is an EMPTY string when the scan found nothing. Remembering the
      // miss matters as much as remembering the hit: without it, anything that
      // is playing but is not a web video (a podcast app, a call, a page with
      // no video id) re-asked every browser for its whole tab list on every
      // single poll.
      if (source === 'other' && title && !artworkUrl && !artwork && !artIsCurrent(title)) {
        if (argv.length >= 2 && argv[0] === title) {
          if (argv[1]) artworkUrl = argv[1];
        } else {
          try { artworkUrl = youtubeThumb(browserTabs(), title); } catch (e) {}
        }
      }

      function browserTabs() {
        const found = [];
        try {
          const sf = Application('Safari');
          if (sf.running()) {
            for (const w of sf.windows()) {
              for (const t of w.tabs()) {
                try { found.push({ url: t.url(), title: t.name() }); } catch (e) {}
              }
            }
          }
        } catch (e) {}
        for (const name of ['Google Chrome', 'Brave Browser', 'Microsoft Edge', 'Arc']) {
          try {
            const br = Application(name);
            if (br.running()) {
              for (const w of br.windows()) {
                for (const t of w.tabs()) {
                  try { found.push({ url: t.url(), title: t.title() }); } catch (e) {}
                }
              }
            }
          } catch (e) {}
        }
        return found;
      }

      function youtubeThumb(tabs, wanted) {
        const re = /(?:youtube\\.com\\/watch[^\\s]*[?&]v=|youtu\\.be\\/|youtube\\.com\\/shorts\\/)([A-Za-z0-9_-]{6,20})/;
        let fallback = null;
        for (const t of tabs) {
          const m = String(t.url || '').match(re);
          if (!m) continue;
          const thumb = 'https://i.ytimg.com/vi/' + m[1] + '/hqdefault.jpg';
          // The playing tab's title starts with the video title.
          if (wanted && String(t.title || '').indexOf(wanted) === 0) return thumb;
          if (!fallback) fallback = thumb;
        }
        return fallback;
      }

      if (source === 'other' && artIsCurrent(title)) artUnchanged = true;
      return JSON.stringify({ title: title, artist: artist, playing: playing, artworkUrl: artworkUrl, artwork: artwork, source: source, elapsed: elapsed, duration: duration, artUnchanged: artUnchanged });
    }
    """

    init?() {
        guard FileManager.default.isExecutableFile(atPath: Self.osascript) else { return nil }
    }

    /// Fetches the current track; completion is called on a background queue.
    /// If the previous fetch is still running (osascript stalled on a permission
    /// dialog), this poll is skipped instead of queueing up behind it.
    func fetch(_ completion: @escaping (NowPlaying?) -> Void) {
        stateLock.lock()
        let busy = inFlight
        if !busy { inFlight = true }
        stateLock.unlock()
        guard !busy else { return }

        queue.async { [weak self] in
            let result = self?.run()
            if let self {
                self.stateLock.lock()
                self.inFlight = false
                self.stateLock.unlock()
            }
            completion(result)
        }
    }

    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let playing: Bool?
        let artworkUrl: String?
        let artwork: String?
        let artUnchanged: Bool?
        let source: String?
        let elapsed: Double?
        let duration: Double?
    }

    /// Title → thumbnail cache so the browsers are only asked again when the
    /// video actually changes (passed into the script as arguments). A lookup
    /// that found nothing is remembered too, as an empty URL, so a track that
    /// simply has no web thumbnail does not re-scan every tab on every poll.
    private var cachedThumbTitle = ""
    private var cachedThumbURL = ""
    private var lastThumbLookup = Date.distantPast

    /// How long a fruitless lookup is trusted before the browsers may be asked
    /// once more. Covers the narrow race where a video's tab title has not
    /// caught up with the track title yet, without ever returning to a scan
    /// per poll.
    private static let thumbRetryInterval: TimeInterval = 60

    /// Sends a playback command. Spotify and Music get their exact scripting
    /// verb, which is the only channel that reliably resumes them: once either
    /// is paused it releases the now-playing session, and the system media
    /// channel then accepts a play command, reports success, and does nothing.
    /// Everything else (browser video, any other app) has no scripting
    /// interface we can count on, so it goes through the system channel — the
    /// same one the keyboard's media keys use.
    ///
    /// Fixed commands only — no user-controlled text ever reaches a script.
    /// Runs on its own queue so a click never waits behind a fetch, with a
    /// watchdog so a stalled permission dialog cannot wedge it.
    func send(_ command: MediaCommand, to source: MediaSource, pressingKeys: Bool = false) {
        // A browser can only be reached by the keyboard's own media keys, and
        // only when the user has allowed it. Everything else goes the way it
        // always did.
        if source == .other, pressingKeys, MediaKeys.isTrusted {
            switch command {
            case .play, .pause: MediaKeys.press(MediaKeys.playPause)
            case .next: MediaKeys.press(MediaKeys.next)
            case .previous: MediaKeys.press(MediaKeys.previous)
            }
            return
        }

        let arguments: [String]
        switch source {
        case .spotify, .music:
            let app = source == .spotify ? "Spotify" : "Music"
            arguments = ["-e", "tell application \"\(app)\" to \(command.scriptVerb)"]
        case .other:
            arguments = ["-l", "JavaScript", "-e", """
            ObjC.import('Foundation');
            $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
            ObjC.bindFunction('MRMediaRemoteSendCommand', ['bool', ['int', 'id']]);
            $.MRMediaRemoteSendCommand(\(command.remoteCode), $());
            """]
        }
        runCommand(arguments, describing: command)
    }

    private func runCommand(_ arguments: [String], describing command: MediaCommand) {
        commandQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.osascript)
            process.arguments = arguments
            process.qualityOfService = .userInitiated
            process.standardOutput = FileHandle.nullDevice
            // Keep the error text rather than discarding it: a refused
            // Automation permission is the difference between "the button does
            // nothing" and a one-line explanation of why.
            let errors = Pipe()
            process.standardError = errors
            do { try process.run() } catch {
                Self.report(command, "could not start osascript: \(error.localizedDescription)")
                return
            }

            let watchdog = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global(qos: .utility)
                .asyncAfter(deadline: .now() + Self.fetchTimeout, execute: watchdog)
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()

            guard process.terminationStatus != 0 else { return }
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Self.report(command, message.isEmpty ? "exit \(process.terminationStatus)" : message)
        }
    }

    /// A failed playback command is worth one line on stderr. It is never shown
    /// in the island — a control that quietly did nothing is confusing, but a
    /// panel that shouts about it would be worse.
    private static func report(_ command: MediaCommand, _ message: String) {
        FileHandle.standardError.write(
            Data("Hash D Island: \(command) command failed — \(message)\n".utf8)
        )
    }

    private func run() -> NowPlaying? {
        // Withhold the remembered title when a fruitless lookup is due another
        // try, which is the one way the script is allowed to ask the browsers
        // about a title it has already seen.
        let retryDue = cachedThumbURL.isEmpty
            && Date().timeIntervalSince(lastThumbLookup) > Self.thumbRetryInterval

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.osascript)
        process.arguments = [
            "-l", "JavaScript", "-e", Self.script,
            retryDue ? "" : cachedThumbTitle,
            cachedThumbURL,
            artworkTitle ?? "",
            cachedArtwork != nil ? "1" : "",
        ]
        process.qualityOfService = .utility
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        // Watchdog: kill the subprocess if it exceeds the timeout, so a stalled
        // osascript can never wedge the media queue.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility)
            .asyncAfter(deadline: .now() + Self.fetchTimeout, execute: watchdog)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let title = payload.title, !title.isEmpty else {
            return nil
        }

        let source = payload.source.flatMap(MediaSource.init(rawValue:)) ?? .other
        // Record the lookup for this title whenever one actually ran — hit or
        // miss — so the browsers are asked once per video, not once per poll.
        if source == .other, title != cachedThumbTitle || retryDue {
            cachedThumbTitle = title
            cachedThumbURL = payload.artworkUrl ?? ""
            lastThumbLookup = Date()
        }

        // The script was told what we already hold; when it says nothing has
        // changed it did none of the work to produce it again, and neither do
        // we.
        let artwork = artworkNow(for: title, payload: payload)
        return NowPlaying(
            title: title,
            artist: payload.artist,
            isPlaying: payload.playing ?? false,
            artwork: artwork,
            source: source,
            elapsed: payload.elapsed,
            duration: payload.duration,
            fetchedAt: Date()
        )
    }

    /// The artwork to publish with THIS snapshot — never a download.
    ///
    /// The cover used to be resolved inline, which meant a track change waited
    /// on an HTTP request with a four-second timeout before the *title* could
    /// reach the screen. Pressing skip therefore looked like it had not worked:
    /// the song had already changed, and the notch was still showing the old
    /// one because it was busy fetching a picture. Nothing here blocks now.
    /// Anything already in hand is returned; anything that needs the network is
    /// started on `artworkQueue` and delivered through `onArtwork` when it
    /// lands, as a second, later update to a track that is already on screen.
    ///
    /// Music's artwork is the exception that stays inline: it arrives as base64
    /// inside the payload we have already paid for, so decoding it is arithmetic
    /// rather than waiting.
    private func artworkNow(for title: String, payload: Payload) -> Data? {
        if payload.artUnchanged == true, let cachedArtwork { return cachedArtwork }

        if let base64 = payload.artwork, let data = Data(base64Encoded: base64),
           data.count <= ArtworkPolicy.maxArtworkBytes {
            cachedArtworkURL = nil
            cachedArtwork = data
            artworkTitle = title
            return data
        }

        guard let url = payload.artworkUrl, !url.isEmpty, ArtworkPolicy.isTrustedURL(url) else {
            cachedArtwork = nil
            cachedArtworkURL = nil
            artworkTitle = nil
            return nil
        }

        if url == cachedArtworkURL, let cached = cachedArtwork { return cached }

        // A new cover. Publish the track without it and go and get it.
        startArtworkDownload(url: url, for: title)
        cachedArtwork = nil
        cachedArtworkURL = nil
        artworkTitle = nil
        return nil
    }

    /// Downloads a cover off the polling queue and hands it back when it lands.
    ///
    /// The cache is only ever written back on `queue`, the same serial queue
    /// `run` uses, so the download touching it cannot race a poll reading it.
    private func startArtworkDownload(url: String, for title: String) {
        guard pendingArtworkURL != url else { return }
        pendingArtworkURL = url
        artworkQueue.async { [weak self] in
            guard let self else { return }
            let data = self.download(url)
            self.queue.async {
                if self.pendingArtworkURL == url { self.pendingArtworkURL = nil }
                guard let data else { return }
                self.cachedArtworkURL = url
                self.cachedArtwork = data
                self.artworkTitle = title
                self.onArtwork?(title, data)
            }
        }
    }

    private func download(_ urlString: String) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        // An ephemeral session driven by ArtworkFetch: nothing is written to the
        // URL cache or disk, a CDN that 302s to a host outside the allowlist is
        // refused mid-flight — so "only these hosts, ever" holds even across
        // redirects, not just for the first URL — and the response is cut off
        // the moment it exceeds the size cap rather than after it has already
        // been held in memory whole.
        let fetch = ArtworkFetch()
        let session = URLSession(configuration: .ephemeral, delegate: fetch, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        task.resume()
        return fetch.wait(upTo: 5, task: task)
    }
}

/// Drives one artwork download under `ArtworkPolicy`.
///
/// Three jobs, all of them limits rather than features:
///  - a redirect is followed only while it stays on the trusted-host allowlist,
///    so the app's single network access can never be bounced to an arbitrary
///    host;
///  - a response that declares, or grows past, the size cap is cancelled
///    mid-flight instead of being buffered whole and judged afterwards;
///  - the finished bytes are handed back under a lock, so a fetch that outruns
///    the caller's timeout can never be writing the buffer while the caller
///    reads it.
private final class ArtworkFetch: NSObject, URLSessionDataDelegate {
    private let lock = NSLock()
    private var buffer = Data()
    private var overflowed = false
    private var failed = false
    private let done = DispatchSemaphore(value: 0)

    /// Blocks until the download finishes or `seconds` elapse, then returns the
    /// bytes (nil on failure, overflow, or timeout). Cancels a task that is
    /// still running so a stalled fetch does not linger.
    func wait(upTo seconds: TimeInterval, task: URLSessionTask) -> Data? {
        guard done.wait(timeout: .now() + seconds) == .success else {
            task.cancel()
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return (failed || overflowed) ? nil : buffer
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let url = request.url?.absoluteString, ArtworkPolicy.isTrustedURL(url) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // A declared length over the cap is refused before a single byte of the
        // body is read.
        if response.expectedContentLength > Int64(ArtworkPolicy.maxArtworkBytes) {
            lock.lock(); overflowed = true; lock.unlock()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        // Chunked responses declare no length, so the running total is what
        // actually enforces the cap.
        if buffer.count + data.count > ArtworkPolicy.maxArtworkBytes {
            overflowed = true
            buffer = Data()
            lock.unlock()
            dataTask.cancel()
            return
        }
        buffer.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if error != nil { failed = true }
        lock.unlock()
        done.signal()
    }
}
