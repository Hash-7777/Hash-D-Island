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
    /// Whether the user has allowed the media keys, read at the moment a button
    /// is pressed so switching it on takes effect without a restart.
    private var pressesKeys: () -> Bool = { false }
    private var samplingInterval: TimeInterval = 0
    private var stateObservers: [NSObjectProtocol] = []
    private var refreshWork: DispatchWorkItem?

    public init() {}

    public func start(presence: LivePresence, pressesKeys: @escaping () -> Bool = { false }) {
        self.presence = presence
        self.pressesKeys = pressesKeys

        // A cover arrives after the track it belongs to, because waiting for it
        // used to hold the title off the screen. It is applied only if that
        // track is still the one showing — by the time an image lands the user
        // may have skipped again, and the previous song's cover is worse than
        // the placeholder.
        reader?.onArtwork = { [weak self] title, data in
            Task { @MainActor [weak self] in self?.applyArtwork(data, for: title) }
        }

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

        startSampling(interval: Self.idleInterval)
    }

    /// Only actual playback earns the brisk poll, because only actual playback
    /// changes anything: the position advances and the progress bar has to keep
    /// up. A paused track sits perfectly still, and an empty notch has nothing
    /// to show at all — in both cases each poll would spend an osascript
    /// subprocess to learn that nothing happened.
    ///
    /// Dropping the rate costs no responsiveness: pressing play is caught by
    /// the CoreAudio and player broadcasts above within a fraction of a second,
    /// and this poll is only the safety net behind them.
    private nonisolated static let activeInterval: TimeInterval = 2
    /// A paused track while the speakers are BUSY — so something else is
    /// playing and this readout is about to be wrong.
    ///
    /// This is the case that used to take twelve seconds to notice. The
    /// CoreAudio signal that should catch it cannot be relied on: a browser
    /// holding an audio session open means starting a video does not CHANGE
    /// whether the device is running, so nothing fires. Polling everything
    /// faster fixed it and tripled the idle cost, which is a bad trade for a
    /// readout. Asking whether audio is running costs nothing and is only ever
    /// true when there is something to find.
    private nonisolated static let contendedInterval: TimeInterval = 2
    /// A paused track and silence. Nothing is going to change until the user
    /// does something, and doing something makes a noise.
    private nonisolated static let pausedInterval: TimeInterval = 12
    /// Nothing playing at all, and nothing to be stale about.
    private nonisolated static let idleInterval: TimeInterval = 15

    private func startSampling(interval: TimeInterval) {
        guard samplingInterval != interval || sampler == nil else { return }
        samplingInterval = interval
        sampler?.stop()
        let sampler = PollingSampler(interval: interval) { [weak self] in self?.refresh() }
        self.sampler = sampler
        sampler.start()
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
        reader?.send(wantsToPlay ? .play : .pause, to: media.source, pressingKeys: pressesKeys())
        scheduleRefresh()
    }

    public func next() {
        guard let media = nowPlaying else { return }
        reader?.send(.next, to: media.source, pressingKeys: pressesKeys())
        skipping()
    }

    public func previous() {
        guard let media = nowPlaying else { return }
        reader?.send(.previous, to: media.source, pressingKeys: pressesKeys())
        skipping()
    }

    /// What a skip does to the panel before the player has answered.
    ///
    /// Play and pause could always flip optimistically, because the button
    /// knows the answer. A skip does not — nobody knows the next title until
    /// the player says so — so it used to change nothing at all for up to a
    /// full poll, and the honest reading of a control that does nothing is that
    /// it is broken. The bar cannot show a position in a track that is being
    /// left, so it goes to the start immediately: that is true of whatever
    /// comes next, and it is the one piece of feedback available at once.
    ///
    /// Then it asks again quickly rather than waiting out the poll — three
    /// times, backing off, which is over inside a second and a half and is the
    /// difference between a skip that lands and one that seems to hang.
    private func skipping() {
        if let progress {
            self.progress = MediaProgress(
                elapsed: 0, duration: progress.duration, isPlaying: progress.isPlaying, at: Date()
            )
        }
        for delay in Self.skipFollowUps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }

    /// When to look again after a skip. The first is as soon as a player could
    /// plausibly have answered; the rest cover a slow one without ever becoming
    /// a poll in their own right.
    private static let skipFollowUps: [TimeInterval] = [0.25, 0.7, 1.5]

    /// Whether a cover that has just finished downloading still belongs on
    /// screen.
    ///
    /// Artwork is fetched off the polling queue so a track can be shown without
    /// waiting for its picture, which means a cover can land after the user has
    /// already skipped past the song it belongs to. Showing it then would put
    /// the wrong album beside the right title — a worse failure than the
    /// placeholder it replaced, and one that would sit there until the next
    /// track change. Pure and package-visible so the checks can pin it without
    /// a player.
    package nonisolated static func acceptsArtwork(
        arrivedFor arrivedTitle: String,
        showing shownTitle: String?
    ) -> Bool {
        guard let shownTitle, !arrivedTitle.isEmpty else { return false }
        return shownTitle == arrivedTitle
    }

    /// Fills in a cover that arrived after its track.
    private func applyArtwork(_ data: Data, for title: String) {
        guard let media = nowPlaying,
              Self.acceptsArtwork(arrivedFor: title, showing: media.title),
              media.artwork != data
        else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            nowPlaying = NowPlaying(
                title: media.title,
                artist: media.artist,
                isPlaying: media.isPlaying,
                artwork: data,
                source: media.source,
                elapsed: media.elapsed,
                duration: media.duration,
                fetchedAt: media.fetchedAt
            )
        }
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
        // Follow the music, not merely the track: a paused song holds the strip
        // but changes nothing, so it is polled as lazily as silence.
        startSampling(interval: Self.interval(
            for: shown, audioElsewhere: audioObserver?.isAudioRunning ?? false
        ))
    }

    /// How often to look, given what is showing. Pure and package-visible: the
    /// choice between these three is what decides how quickly the notch notices
    /// you have switched to something else.
    package nonisolated static func interval(
        for shown: NowPlaying?,
        audioElsewhere: Bool
    ) -> TimeInterval {
        guard let shown else { return idleInterval }
        if shown.isPlaying { return activeInterval }
        // Paused, but the speakers are busy: whatever is making that sound is
        // what should be on the notch, so look again shortly.
        return audioElsewhere ? contendedInterval : pausedInterval
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
