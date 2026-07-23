import Foundation
import SwiftUI
import HashDIslandKit

/// Track position, published separately from `NowPlaying` so a steadily
/// playing track causes no identity churn — views interpolate from here.
public struct MediaProgress: Equatable {
    public let elapsed: Double
    public let duration: Double
    public let isPlaying: Bool
    public let at: Date

    /// Position now: the last reported position plus wall time while playing.
    public func current(now: Date) -> Double {
        let base = isPlaying ? elapsed + now.timeIntervalSince(at) : elapsed
        return min(max(base, 0), duration)
    }
}

/// Publishes the current Now Playing track and signals live presence while media
/// is present. Polls on a light interval; the MediaRemote fetch is async and
/// returns on a background queue, so results hop to the main actor to publish.
///
/// Visibility rule (iPhone-like): a track holds the notch for as long as it
/// exists — playing OR paused — so pausing never costs you the artwork, the
/// title, or the button that resumes it. Only the audio bars react to the
/// play state, resting as dots while paused. The track clears when the system
/// reports no item at all: the player quit, or the tab closed.
@MainActor
public final class MediaMonitor: ObservableObject {
    @Published public private(set) var nowPlaying: NowPlaying?
    @Published public private(set) var progress: MediaProgress?
    /// System output volume 0–100, shown as the panel's slider.
    @Published public private(set) var systemVolume: Int?

    private let reader = MediaRemoteReader()
    private var sampler: PollingSampler?
    private weak var presence: LivePresence?
    private var lastVolumeTouch = Date.distantPast
    /// When the last playback command was sent. A player takes a moment to
    /// react, and a poll landing inside that moment reports the state we were
    /// changing away from — which used to snap the button straight back and
    /// read as "the button did nothing".
    private var lastCommand = Date.distantPast
    private static let commandSettleWindow: TimeInterval = 1.5
    private var audioObserver: AudioActivityObserver?
    private var stateObservers: [NSObjectProtocol] = []
    private var refreshWork: DispatchWorkItem?

    public init() {}

    public func start(presence: LivePresence) {
        self.presence = presence

        // Instant reaction: CoreAudio signals the moment audio starts or stops
        // anywhere, and Spotify/Music broadcast their play-state changes. The
        // poll below is only the safety net (seek positions, sources that
        // signal nothing).
        audioObserver = AudioActivityObserver { [weak self] in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        let center = DistributedNotificationCenter.default()
        for name in [
            "com.spotify.client.PlaybackStateChanged",
            "com.apple.Music.playerInfo",
            "com.apple.iTunes.playerInfo",
        ] {
            stateObservers.append(center.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            })
        }

        sampler = PollingSampler(interval: 2.0) { [weak self] in self?.refresh() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        audioObserver = nil
        let center = DistributedNotificationCenter.default()
        stateObservers.forEach(center.removeObserver)
        stateObservers.removeAll()
        refreshWork?.cancel()
        refreshWork = nil
        presence?.setActive("media", false)
    }

    /// Coalesces the burst of signals audio startup produces into one fetch.
    private func refreshSoon() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: Controls

    public func togglePlayPause() {
        guard let media = nowPlaying else { return }
        let wantsToPlay = !media.isPlaying
        // Optimistic flip so the button feels instant, and an explicit play or
        // pause rather than a toggle so the player is told what we showed
        // rather than asked to guess.
        setPlaying(wantsToPlay)
        lastCommand = Date()
        reader?.send(wantsToPlay ? .play : .pause, to: media.source)
        scheduleRefresh()
    }

    public func next() {
        guard let media = nowPlaying else { return }
        reader?.send(.next, to: media.source)
        scheduleRefresh()
    }

    public func previous() {
        guard let media = nowPlaying else { return }
        reader?.send(.previous, to: media.source)
        scheduleRefresh()
    }

    /// Slider input: CoreAudio is a direct call, so every tick of the drag is
    /// applied immediately — zero latency, perfectly smooth.
    public func setVolume(_ volume: Int) {
        let clamped = min(max(volume, 0), 100)
        systemVolume = clamped
        lastVolumeTouch = Date()
        SystemVolume.set(clamped)
    }

    private func setPlaying(_ playing: Bool) {
        guard let media = nowPlaying else { return }
        let now = Date()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            nowPlaying = NowPlaying(
                title: media.title,
                artist: media.artist,
                isPlaying: playing,
                artwork: media.artwork,
                source: media.source,
                elapsed: progress?.current(now: now) ?? media.elapsed,
                duration: media.duration,
                fetchedAt: now
            )
        }
        if let progress {
            self.progress = MediaProgress(
                elapsed: progress.current(now: now),
                duration: progress.duration,
                isPlaying: playing,
                at: now
            )
        }
        // The track is still present whether it's now playing or paused, so the
        // strip stays up either way.
        presence?.setActive("media", true)
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: Polling

    private func refresh() {
        guard let reader else { return }
        reader.fetch { snapshot in
            Task { @MainActor [weak self] in self?.apply(snapshot) }
        }
    }

    private func apply(_ snapshot: NowPlaying?) {
        // Keep whatever track exists — playing OR paused, any source. Both the
        // compact strip and the panel card stay up while a track is present so
        // the artwork and controls survive a pause; they clear only when the
        // system reports no item at all (the app quit, the tab closed).
        let shown = settling(snapshot)

        if shown != nowPlaying {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { nowPlaying = shown }
        }

        if let shown, let elapsed = shown.elapsed, let duration = shown.duration, duration > 0 {
            progress = MediaProgress(
                elapsed: elapsed,
                duration: duration,
                isPlaying: shown.isPlaying,
                at: shown.fetchedAt
            )
        } else {
            progress = nil
        }

        // Track the system volume (changed via keys, Control Center, etc.)
        // unless the user just moved our slider — their hand wins.
        if Date().timeIntervalSince(lastVolumeTouch) > 2,
           let volume = SystemVolume.read(),
           volume != systemVolume {
            systemVolume = volume
        }

        presence?.setActive("media", shown != nil)
    }

    /// Whether a polled play state should be trusted, or the state the button
    /// already showed kept for a moment longer.
    ///
    /// A player takes a beat to obey. A poll landing inside that beat reports
    /// the state we were changing away from, and taking it at face value snaps
    /// the button back — which reads as the button having done nothing, even
    /// though the track starts a moment later. Outside the window the player is
    /// always right: it is the user's Spotify, not our guess, that decides.
    ///
    /// Pure and package-visible so the checks can pin it without a player.
    package nonisolated static func keepsOptimisticPlayState(
        secondsSinceCommand: TimeInterval,
        window: TimeInterval,
        polledIsPlaying: Bool,
        optimisticIsPlaying: Bool
    ) -> Bool {
        guard polledIsPlaying != optimisticIsPlaying else { return false }
        return secondsSinceCommand < window
    }

    /// Everything a poll reports is taken as-is — the track, the artwork, the
    /// position — except the play state while a command is still settling.
    private func settling(_ snapshot: NowPlaying?) -> NowPlaying? {
        guard let snapshot, let optimistic = nowPlaying else { return snapshot }
        guard Self.keepsOptimisticPlayState(
            secondsSinceCommand: Date().timeIntervalSince(lastCommand),
            window: Self.commandSettleWindow,
            polledIsPlaying: snapshot.isPlaying,
            optimisticIsPlaying: optimistic.isPlaying
        ) else { return snapshot }

        return NowPlaying(
            title: snapshot.title,
            artist: snapshot.artist,
            isPlaying: optimistic.isPlaying,
            artwork: snapshot.artwork,
            source: snapshot.source,
            elapsed: snapshot.elapsed,
            duration: snapshot.duration,
            fetchedAt: snapshot.fetchedAt
        )
    }
}
