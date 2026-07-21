import Foundation

/// The current track/video playing anywhere on the Mac.
public struct NowPlaying: Equatable {
    public let title: String
    public let artist: String?
    public let isPlaying: Bool
    public let artwork: Data?
}

/// Decides which artwork URLs the app is willing to download. Spotify's
/// scripting interface hands us a URL string; we only ever fetch it when it is
/// HTTPS and points at Spotify's own image CDN — never an arbitrary host, never
/// a non-HTTPS scheme (a `file://` or `http://` URL is refused outright). This
/// is the app's only network access, so the policy is deliberately narrow and
/// covered by HashNotchChecks.
package enum ArtworkPolicy {
    /// Hosts Spotify serves album art from.
    private static let trustedSuffixes = ["scdn.co", "spotifycdn.com"]

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

    private let stateLock = NSLock()
    private var inFlight = false

    private var cachedArtworkURL: String?
    private var cachedArtwork: Data?

    private static let osascript = "/usr/bin/osascript"

    /// How long one osascript round-trip may take before we kill it (it can
    /// stall indefinitely behind a macOS Automation permission dialog).
    private static let fetchTimeout: TimeInterval = 10

    private static let script = """
    function run() {
      ObjC.import('Foundation');
      let title = null, artist = null, playing = false, artworkUrl = null, artwork = null;

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
          }
        }
      }

      try {
        const sp = Application('Spotify');
        if (sp.running() && String(sp.playerState()) === 'playing') {
          artworkUrl = sp.currentTrack.artworkUrl();
          if (!title) { title = sp.currentTrack.name(); artist = sp.currentTrack.artist(); playing = true; }
        }
      } catch (e) {}

      try {
        const mu = Application('Music');
        if (mu.running() && String(mu.playerState()) === 'playing') {
          if (!title) { title = mu.currentTrack.name(); artist = mu.currentTrack.artist(); playing = true; }
          const arts = mu.currentTrack.artworks;
          if (arts.length > 0) {
            const raw = arts[0].rawData();
            artwork = $.NSString.alloc.initWithDataEncoding(raw.base64EncodedDataWithOptions(0), $.NSUTF8StringEncoding).js;
          }
        }
      } catch (e) {}

      return JSON.stringify({ title: title, artist: artist, playing: playing, artworkUrl: artworkUrl, artwork: artwork });
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
    }

    private func run() -> NowPlaying? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.osascript)
        process.arguments = ["-l", "JavaScript", "-e", Self.script]
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

        let artwork = resolveArtwork(url: payload.artworkUrl, base64: payload.artwork)
        return NowPlaying(
            title: title,
            artist: payload.artist,
            isPlaying: payload.playing ?? false,
            artwork: artwork
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
        var result: Data?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, data.count <= ArtworkPolicy.maxArtworkBytes {
                result = data
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }
}
