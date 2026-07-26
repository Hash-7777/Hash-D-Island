import Foundation

/// Reads Now Playing straight from MediaRemote, in process, artwork included.
///
/// ## Why this exists, and why it did not before
///
/// Everything the panel shows about a track used to come out of an `osascript`
/// subprocess, because a direct MediaRemote call had once crashed the app and
/// because the in-process route appeared to hand over no artwork — so covers
/// had to be scraped from whichever app was playing: Spotify's scripting
/// interface, Apple Music's raw bytes, or a sweep of every browser tab looking
/// for a YouTube video id. Each of those needs Automation permission, and none
/// of them helps for anything else. A track playing in Anghami, TV, Podcasts,
/// VLC or any other app got a placeholder tile, because nobody had written a
/// scraper for it.
///
/// That conclusion was drawn from the wrong call.
/// `MRNowPlayingRequest.localNowPlayingItem.nowPlayingInfo` — the route the
/// subprocess used — really does withhold the image: it publishes
/// `ArtworkMIMEType`, `ArtworkIdentifier` and the pixel dimensions, but no
/// data, and its `artwork` property is nil. `MRMediaRemoteGetNowPlayingInfo`,
/// the callback-based call, returns the same dictionary WITH
/// `kMRMediaRemoteNowPlayingInfoArtworkData` in it. Measured against a YouTube
/// video playing in Chrome: 256 KB of JPEG, on 25 consecutive calls, worst
/// round trip 17 ms, no crash.
///
/// So the app now asks the system directly, and gets for free what it was
/// scraping for:
///
///   * **Artwork for anything.** Whatever is playing, from any app, including
///     ones nobody wrote support for.
///   * **No Automation prompts to read.** No Apple Events are sent at all.
///     Reading a track no longer asks Spotify, Music or any browser anything,
///     so it can no longer trigger a permission dialog or stall behind one.
///   * **No network request for a cover**, because the bytes are already here.
///   * **No subprocess per poll** — 17 ms in process against roughly 90 ms and
///     a process spawn.
///
/// The old path is kept as a fallback rather than deleted. These are private
/// APIs; this was measured on one macOS version, and the app supports several.
/// If the symbols are missing or the call yields nothing, the caller falls back
/// to the subprocess exactly as before.
///
/// Read-only throughout: this asks what is playing and never sets anything.
package final class NowPlayingDirect {
    /// One track, as MediaRemote describes it.
    package struct Snapshot {
        package let title: String
        package let artist: String?
        package let isPlaying: Bool
        package let elapsed: Double?
        package let duration: Double?
        package let artwork: Data?
        /// The bundle id of the app that is playing, when the system says.
        /// Used only to pick a control channel — never to decide whether a
        /// track is worth showing, so an app nobody has heard of still works.
        package let bundleIdentifier: String?
    }

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    private typealias SetElapsedFn = @convention(c) (Double) -> Void
    private typealias GetClientFn = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private typealias ClientBundleFn = @convention(c) (AnyObject?) -> Unmanaged<CFString>?

    private let getInfo: GetInfoFn
    private let setElapsed: SetElapsedFn?
    private let getClient: GetClientFn?
    private let clientBundle: ClientBundleFn?

    /// Nil when MediaRemote is not where it is expected, or does not export the
    /// call. Every use site treats that as "fall back", never as a failure.
    init?() {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        else { return nil }
        getInfo = unsafeBitCast(symbol, to: GetInfoFn.self)
        setElapsed = dlsym(handle, "MRMediaRemoteSetElapsedTime")
            .map { unsafeBitCast($0, to: SetElapsedFn.self) }
        getClient = dlsym(handle, "MRMediaRemoteGetNowPlayingClient")
            .map { unsafeBitCast($0, to: GetClientFn.self) }
        clientBundle = dlsym(handle, "MRNowPlayingClientGetBundleIdentifier")
            .map { unsafeBitCast($0, to: ClientBundleFn.self) }
    }

    /// Asks which app is playing. Answers with nil rather than failing.
    ///
    /// Used ONLY to choose how a command is sent — Spotify and Music need their
    /// own scripting to resume reliably, everything else does not have any. It
    /// deliberately has no say in whether a track is shown, so an app nobody
    /// has ever heard of appears on the notch exactly like a known one.
    func readOwner(on queue: DispatchQueue, completion: @escaping (String?) -> Void) {
        guard let getClient, let clientBundle else { completion(nil); return }
        getClient(queue) { client in
            guard let client else { completion(nil); return }
            completion(clientBundle(client)?.takeUnretainedValue() as String?)
        }
    }

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    /// Whether this build of macOS will let us move the playhead.
    var canSeek: Bool { setElapsed != nil }

    /// The largest cover the app will hold. The system hands these over
    /// directly, so nothing is downloaded — but a bound still belongs here,
    /// because this data is decoded into an image on the main thread.
    package static let maxArtworkBytes = 8_000_000

    /// Reads the current track. The completion runs on `queue`.
    ///
    /// Never blocks: this is the callback form of the API, so a slow or absent
    /// answer costs nothing. A caller that gets nil should try the fallback.
    func read(on queue: DispatchQueue, completion: @escaping (Snapshot?) -> Void) {
        getInfo(queue) { info in
            guard let info else { completion(nil); return }
            completion(Self.snapshot(from: info))
        }
    }

    /// Turns MediaRemote's dictionary into a snapshot, or nil if there is no
    /// track worth showing.
    ///
    /// Package-visible and pure so the checks can pin the parsing — including
    /// the cases that matter and cannot be staged on demand: a dictionary with
    /// no title, an oversized cover, a negative duration.
    package static func snapshot(from info: [String: Any]) -> Snapshot? {
        func string(_ key: String) -> String? {
            (info["kMRMediaRemoteNowPlayingInfo" + key] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        func number(_ key: String) -> Double? {
            (info["kMRMediaRemoteNowPlayingInfo" + key] as? NSNumber)?.doubleValue
        }

        // No title, nothing to show. Every other field is optional garnish.
        guard let title = string("Title") else { return nil }

        let artwork = (info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)
            .flatMap { $0.isEmpty || $0.count > maxArtworkBytes ? nil : $0 }

        // A duration of zero is what a live stream reports, and dividing a
        // progress bar by it produces either a crash or a full bar. Treated as
        // "no duration", which the panel already knows how to draw.
        let duration = number("Duration").flatMap { $0 > 0 ? $0 : nil }
        let elapsed = number("ElapsedTime").map { max(0, $0) }

        return Snapshot(
            title: title,
            artist: string("Artist"),
            isPlaying: (number("PlaybackRate") ?? 0) > 0,
            elapsed: elapsed,
            duration: duration,
            artwork: artwork,
            bundleIdentifier: nil
        )
    }

    /// Which control channel an app answers to.
    ///
    /// The only place a bundle id is matched by name, and it is worth being
    /// clear about why that is not the thing the app was asked to stop doing.
    /// Recognising apps in order to DISPLAY them would mean anything unlisted
    /// gets nothing — which is what used to happen, and why Anghami or TV drew
    /// a placeholder. Nothing here affects display: every app is read, shown
    /// and given artwork identically. This picks how a *command* is delivered,
    /// and that genuinely differs — Spotify and Music release the now-playing
    /// session when paused, so only their own scripting can resume them, while
    /// everything else has no scripting interface to prefer.
    ///
    /// An app that is not listed is not unsupported; it takes the same route as
    /// every other app, which is the route that suits it.
    package static func source(forBundleIdentifier bundle: String?) -> MediaSource {
        switch bundle?.lowercased() {
        case "com.spotify.client": return .spotify
        case "com.apple.music", "com.apple.itunes": return .music
        default: return .other
        }
    }

    /// Moves the playhead. Only offered when the symbol exists.
    func seek(to seconds: Double) {
        setElapsed?(max(0, seconds))
    }
}
