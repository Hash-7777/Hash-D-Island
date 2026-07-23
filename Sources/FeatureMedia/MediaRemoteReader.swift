import Foundation

/// Which app owns the current track — controls only exist for apps we can
/// script (Spotify and Music); everything else is display-only.
public enum MediaSource: String {
    case spotify
    case music
    case other
}

/// A playback command the user can send from the panel.
public enum MediaCommand {
    case playPause
    case next
    case previous
}

/// The current track/video playing anywhere on the Mac.
public struct NowPlaying {
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
/// covered by HashNotchChecks.
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
    private let queue = DispatchQueue(label: "com.hashnotch.media.nowplaying")
    /// Commands run on their own queue so a click NEVER waits behind an
    /// in-flight fetch — play/pause must feel instant.
    private let commandQueue = DispatchQueue(label: "com.hashnotch.media.commands", qos: .userInitiated)

    private let stateLock = NSLock()
    private var inFlight = false

    private var cachedArtworkURL: String?
    private var cachedArtwork: Data?

    private static let osascript = "/usr/bin/osascript"

    /// How long one osascript round-trip may take before we kill it (it can
    /// stall indefinitely behind a macOS Automation permission dialog).
    private static let fetchTimeout: TimeInterval = 10

    private static let script = """
    function run(argv) {
      ObjC.import('Foundation');
      let title = null, artist = null, playing = false, artworkUrl = null, artwork = null;
      let source = 'other', elapsed = null, duration = null;

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
              artworkUrl = sp.currentTrack.artworkUrl();
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
              const arts = mu.currentTrack.artworks;
              if (arts.length > 0) {
                const raw = arts[0].rawData();
                artwork = $.NSString.alloc.initWithDataEncoding(raw.base64EncodedDataWithOptions(0), $.NSUTF8StringEncoding).js;
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
      if (source === 'other' && title && !artworkUrl && !artwork) {
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

      return JSON.stringify({ title: title, artist: artist, playing: playing, artworkUrl: artworkUrl, artwork: artwork, source: source, elapsed: elapsed, duration: duration });
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
    /// verb; everything else (browser video, any app) goes through the
    /// system's MediaRemote command channel — the same one the keyboard's
    /// media keys use. Fixed commands only — no user-controlled text ever
    /// reaches a script. Runs on the same serial queue as fetches so osascript
    /// calls never overlap, with the same watchdog so a stalled permission
    /// dialog cannot wedge the queue.
    func send(_ command: MediaCommand, to source: MediaSource) {
        let arguments: [String]
        switch source {
        case .spotify, .music:
            let app = source == .spotify ? "Spotify" : "Music"
            let verb: String
            switch command {
            case .playPause: verb = "playpause"
            case .next: verb = "next track"
            case .previous: verb = "previous track"
            }
            arguments = ["-e", "tell application \"\(app)\" to \(verb)"]
        case .other:
            // kMRTogglePlayPause = 2, kMRNextTrack = 4, kMRPreviousTrack = 5.
            let code: Int
            switch command {
            case .playPause: code = 2
            case .next: code = 4
            case .previous: code = 5
            }
            arguments = ["-l", "JavaScript", "-e", """
            ObjC.import('Foundation');
            $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
            ObjC.bindFunction('MRMediaRemoteSendCommand', ['bool', ['int', 'id']]);
            $.MRMediaRemoteSendCommand(\(code), $());
            """]
        }
        runCommand(arguments)
    }

    private func runCommand(_ arguments: [String]) {
        commandQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.osascript)
            process.arguments = arguments
            process.qualityOfService = .userInitiated
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return }

            let watchdog = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global(qos: .utility)
                .asyncAfter(deadline: .now() + Self.fetchTimeout, execute: watchdog)
            process.waitUntilExit()
            watchdog.cancel()
        }
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

        let artwork = resolveArtwork(url: payload.artworkUrl, base64: payload.artwork)
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

    /// Resolve artwork: prefer a downloaded URL (Spotify), else base64 (Music).
    /// Downloads are cached by URL so we don't refetch the same image each poll,
    /// and only URLs passing `ArtworkPolicy` are ever fetched.
    private func resolveArtwork(url: String?, base64: String?) -> Data? {
        if let url, !url.isEmpty {
            guard ArtworkPolicy.isTrustedURL(url) else { return nil }
            if url == cachedArtworkURL, let cached = cachedArtwork { return cached }
            let data = download(url)
            cachedArtworkURL = url
            cachedArtwork = data
            return data
        }
        if let base64, let data = Data(base64Encoded: base64),
           data.count <= ArtworkPolicy.maxArtworkBytes {
            return data
        }
        return nil
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
