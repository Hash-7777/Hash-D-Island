import Foundation

/// The current track/video playing anywhere on the Mac.
public struct NowPlaying: Equatable {
    public let title: String
    public let artist: String?
    public let isPlaying: Bool
    public let artwork: Data?
}

/// Reads system-wide "Now Playing" on all macOS versions — including 15.4+/26,
/// where Apple locked the direct MediaRemote call behind an entitlement.
///
/// Universal title / artist / play-state come from `MRNowPlayingRequest` via a
/// short `osascript` subprocess (works on 26, and can't crash us). Artwork is
/// null through that path on 15.4+, so it is pulled straight from Spotify
/// (`artwork url`, downloaded) or Apple Music (raw data) when they're the
/// player. Browsers/other apps get no art (a tasteful placeholder is shown).
final class MediaRemoteReader {
    private let scriptURL: URL
    private let queue = DispatchQueue(label: "com.hashnotch.media.nowplaying")

    private var cachedArtworkURL: String?
    private var cachedArtwork: Data?

    private static let osascript = "/usr/bin/osascript"

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
        scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashnotch-nowplaying.js")
        guard writeScriptIfNeeded() else { return nil }
    }

    private func writeScriptIfNeeded() -> Bool {
        // Always rewrite so script updates take effect between builds.
        return (try? Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)) != nil
    }

    /// Fetches the current track; completion is called on a background queue.
    func fetch(_ completion: @escaping (NowPlaying?) -> Void) {
        queue.async { [weak self] in
            completion(self?.run())
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
        _ = writeScriptIfNeeded()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.osascript)
        process.arguments = ["-l", "JavaScript", scriptURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

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
    /// Downloads are cached by URL so we don't refetch the same image each poll.
    private func resolveArtwork(url: String?, base64: String?) -> Data? {
        if let url, !url.isEmpty {
            if url == cachedArtworkURL, let cached = cachedArtwork { return cached }
            let data = download(url)
            cachedArtworkURL = url
            cachedArtwork = data
            return data
        }
        if let base64, let data = Data(base64Encoded: base64) { return data }
        return nil
    }

    private func download(_ urlString: String) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        var result: Data?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }
}
