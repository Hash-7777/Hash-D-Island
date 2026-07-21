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
/// The trick: run the query in a short `osascript` (JavaScript for Automation)
/// subprocess. JXA reaches `MRNowPlayingRequest.localNowPlayingItem` through the
/// system script runtime, which still works, and — crucially — runs in a
/// separate process, so if the private API ever misbehaves it can never crash
/// HashNotch. Output is parsed as JSON.
final class MediaRemoteReader {
    private let scriptURL: URL
    private let queue = DispatchQueue(label: "com.hashnotch.media.nowplaying")

    private static let osascript = "/usr/bin/osascript"

    private static let script = """
    function run() {
      ObjC.import('Foundation');
      const bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
      bundle.load;
      const cls = $.NSClassFromString('MRNowPlayingRequest');
      if (!cls) return JSON.stringify({ playing: false });
      const item = cls.localNowPlayingItem;
      if (!item || item.isNil()) return JSON.stringify({ playing: false });
      const info = item.nowPlayingInfo;
      if (!info || info.isNil()) return JSON.stringify({ playing: false });
      function str(key) { const v = info.objectForKey(key); return (v && !v.isNil()) ? ObjC.unwrap(v) : null; }
      const rate = str('kMRMediaRemoteNowPlayingInfoPlaybackRate');
      let artwork = null;
      const artData = info.objectForKey('kMRMediaRemoteNowPlayingInfoArtworkData');
      if (artData && !artData.isNil()) {
        try {
          artwork = $.NSString.alloc.initWithDataEncoding(artData.base64EncodedDataWithOptions(0), $.NSUTF8StringEncoding).js;
        } catch (e) { artwork = null; }
      }
      return JSON.stringify({
        title: str('kMRMediaRemoteNowPlayingInfoTitle'),
        artist: str('kMRMediaRemoteNowPlayingInfoArtist'),
        playing: rate ? (rate > 0) : false,
        artwork: artwork
      });
    }
    """

    init?() {
        guard FileManager.default.isExecutableFile(atPath: Self.osascript) else { return nil }
        scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashnotch-nowplaying.js")
        guard writeScriptIfNeeded() else { return nil }
    }

    private func writeScriptIfNeeded() -> Bool {
        if FileManager.default.fileExists(atPath: scriptURL.path) { return true }
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
        let artwork: String?
    }

    private func run() -> NowPlaying? {
        guard writeScriptIfNeeded() else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.osascript)
        process.arguments = ["-l", "JavaScript", scriptURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let title = payload.title, !title.isEmpty else {
            return nil
        }
        let artwork = payload.artwork.flatMap { Data(base64Encoded: $0) }
        return NowPlaying(
            title: title,
            artist: payload.artist,
            isPlaying: payload.playing ?? false,
            artwork: artwork
        )
    }
}
