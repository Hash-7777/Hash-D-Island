import Foundation

/// The current track/video playing anywhere on the Mac.
public struct NowPlaying: Equatable {
    public let title: String
    public let artist: String?
    public let isPlaying: Bool
    public let artwork: Data?
}

/// Reads system-wide "Now Playing".
///
/// The simple path is the private MediaRemote framework
/// (`MRMediaRemoteGetNowPlayingInfo`), but Apple restricted it on recent macOS
/// (15.4+/26): the symbol still resolves, yet calling it now traps. Rather than
/// crash, this reader is disabled — it returns nil and the media feature shows
/// nothing. Re-enabling needs the signed `mediaremote-adapter` helper approach,
/// which loads MediaRemote through a system-trusted path.
final class MediaRemoteReader {
    init?() {
        // Disabled on purpose: calling MediaRemote directly crashes on this OS.
        return nil
    }

    func fetch(_ completion: @escaping (NowPlaying?) -> Void) {
        completion(nil)
    }
}
