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

    /// Why the controls could not reach what is playing — set only once a
    /// command has demonstrably failed, and cleared the moment one works.
    @Published public private(set) var controlProblem: ControlProblem?

    /// The reason a playback command did not take effect.
    ///
    /// Deliberately discovered by MEASUREMENT rather than by recognising the
    /// app that is playing. The alternative was a list of browser bundle ids to
    /// check against, which would be wrong for every browser not on it and
    /// would need editing forever; asking whether the player actually obeyed
    /// works for anything, including apps that did not exist when this was
    /// written.
    public enum ControlProblem: Equatable, Sendable {
        /// Browser control is switched off, so the only channel that reaches a
        /// browser was never tried.
        case browserControlOff
        /// It is switched on, but macOS has not granted Accessibility, so the
        /// media keys are dropped before they leave the app.
        case accessibilityMissing
    }

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
    /// Consecutive looks that found no track while audio was running. Bounds
    /// the chase after a sound that has no now-playing session behind it.
    private var fruitlessLooks = 0
    /// The play state most recently asked for, and when. Once the settle window
    /// has passed, a player still disagreeing with this did not obey.
    private var pendingRequest: (wanted: Bool, at: Date)?
    private var stateObservers: [NSObjectProtocol] = []
    private var refreshWork: DispatchWorkItem?

    public init() {}

    public func start(presence: LivePresence, pressesKeys: @escaping () -> Bool = { false }) {
        self.presence = presence
        self.pressesKeys = pressesKeys

        // Say plainly, once, when the app is set up to control browser video
        // but macOS will not let it. This is worth a line on stderr rather than
        // only a notice in the panel, because the state it reports is one the
        // user cannot see: the Accessibility switch can READ as on while the
        // permission is not in force. macOS records the approval against the
        // exact build it was given, so installing a new version of an app that
        // is only ad-hoc signed silently invalidates it — the switch stays on,
        // and every media key is dropped.
        if pressesKeys(), !MediaKeys.isTrusted {
            FileHandle.standardError.write(Data("""
            Hash D Island: browser control is switched on, but macOS is not \
            allowing this app to press the media keys. The Accessibility \
            switch may still look on — a new build has to be approved afresh. \
            Switching it off and on does NOT clear the stale entry; remove \
            Hash D Island with the minus button and let it add itself back.

            """.utf8))
        }

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
    /// How many brisk looks a sound with no track behind it earns before the
    /// reader stops chasing it. Six at the contended interval is about twelve
    /// seconds — long enough for any player to publish itself, short enough
    /// that a video call does not cost a subprocess every two seconds for an
    /// hour.
    private nonisolated static let fruitlessLookLimit = 6

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
        // Remember what was asked for, so a poll after the settle window can
        // tell the difference between a player that is slow and one that never
        // obeyed at all.
        pendingRequest = (wanted: wantsToPlay, at: Date())
        reader?.send(wantsToPlay ? .play : .pause, to: media.source, pressingKeys: pressesKeys())
        scheduleRefresh()
    }

    public func next() {
        guard let media = nowPlaying else { return }
        noteIfUnreachable(media.source)
        reader?.send(.next, to: media.source, pressingKeys: pressesKeys())
        skipping()
    }

    public func previous() {
        guard let media = nowPlaying else { return }
        noteIfUnreachable(media.source)
        reader?.send(.previous, to: media.source, pressingKeys: pressesKeys())
        skipping()
    }

    /// Re-test whether the controls can reach anything, and drop the notice if
    /// they now can.
    ///
    /// Called when the panel shows the notice again. Granting Accessibility
    /// happens entirely outside this app and tells it nothing, so the only way
    /// to find out is to ask — and the moment somebody is looking at the
    /// warning is exactly when it must be current.
    public func recheckControl() {
        guard controlProblem != nil else { return }
        controlProblem = Self.controlProblem(
            browserControlOn: pressesKeys(),
            accessibilityGranted: MediaKeys.isTrusted
        )
    }

    /// Say straight away when a command cannot possibly land.
    ///
    /// Play and pause find this out by measurement, which is exact but takes
    /// the settle window to conclude. A skip has no equivalent: nobody knows
    /// what the next title should be, so "the title did not change" cannot tell
    /// a refused command apart from a single video with nothing to skip to, and
    /// guessing would put a warning under a track that is behaving perfectly.
    ///
    /// This case needs no guessing. Anything that is not Spotify or Music has
    /// no scripting interface to fall back on, so the media keys are the only
    /// channel to it — and with the switch off, or Accessibility ungranted,
    /// those keys are never sent. The command is known to be going nowhere
    /// before it is sent, so the panel can say so at once.
    private func noteIfUnreachable(_ source: MediaSource) {
        guard source == .other else { return }
        let canPress = pressesKeys() && MediaKeys.isTrusted
        guard !canPress else { return }
        controlProblem = Self.controlProblem(
            browserControlOn: pressesKeys(),
            accessibilityGranted: MediaKeys.isTrusted
        )
    }

    /// What a skip does to the panel before the player has answered: ask again,
    /// quickly, and change nothing else.
    ///
    /// It briefly did more than that, and the extra was a mistake worth
    /// recording. Play and pause can flip optimistically because the button
    /// knows the answer; a skip does not, so to give the press *some* immediate
    /// feedback the progress bar was sent to 0:00 on the reasoning that a new
    /// track starts at the beginning. That reasoning only holds if the skip
    /// actually happens. On a browser video — where the command cannot work at
    /// all without Accessibility — the track carried on playing while the panel
    /// showed a timeline reset to zero and frozen there. The control did
    /// nothing AND the readout lied about it, which is strictly worse than the
    /// unresponsive control it was meant to fix.
    ///
    /// So nothing is invented here. The three quick follow-ups are the whole
    /// answer: the first lands inside a quarter of a second, which is fast
    /// enough to feel like a response when the skip works, and shows nothing at
    /// all when it does not.
    private func skipping() {
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

        // Drop the notice the moment its cause is gone, without waiting for the
        // user to press anything.
        //
        // It used to clear only when a command succeeded, so after granting the
        // permission the warning sat there until something was played — which
        // reads as the app not having noticed, on the very screen that just
        // told them to go and fix it. Granting Accessibility does not come back
        // through the app in any other way, so the poll is where it is seen.
        if controlProblem != nil,
           Self.controlProblem(
               browserControlOn: pressesKeys(),
               accessibilityGranted: MediaKeys.isTrusted
           ) == nil {
            controlProblem = nil
        }

        // Did the last command actually take? Outside the settle window the
        // player has had its chance, so a state still disagreeing with what was
        // asked for means the command went nowhere. The system's media channel
        // reports success either way — measured, on a live browser video: pause
        // returned true and the playback rate stayed at 1 — so believing its
        // answer is exactly how a button comes to look broken.
        if let pending = pendingRequest,
           Date().timeIntervalSince(pending.at) > Self.commandSettleWindow {
            if let shown, shown.isPlaying != pending.wanted {
                controlProblem = Self.controlProblem(
                    browserControlOn: pressesKeys(),
                    accessibilityGranted: MediaKeys.isTrusted
                )
            } else {
                controlProblem = nil
            }
            pendingRequest = nil
        }

        presence?.setActive("media", shown != nil)

        // Count the looks that found nothing while the speakers were busy, so
        // chasing a sound with no track behind it gives up rather than running
        // for the length of a call. Anything else resets it — including the
        // sound stopping — so the next thing to start is chased just as
        // promptly.
        let audioRunning = audioObserver?.isAudioRunning ?? false
        if shown == nil, audioRunning {
            fruitlessLooks += 1
        } else {
            fruitlessLooks = 0
        }

        // Follow the music, not merely the track: a paused song holds the strip
        // but changes nothing, so it is polled as lazily as silence.
        startSampling(interval: Self.interval(
            for: shown, audioElsewhere: audioRunning, fruitlessLooks: fruitlessLooks
        ))
    }

    /// How often to look, given what is showing. Pure and package-visible: the
    /// choice between these is what decides how quickly the notch notices you
    /// have started or switched to something else.
    package nonisolated static func interval(
        for shown: NowPlaying?,
        audioElsewhere: Bool,
        fruitlessLooks: Int = 0
    ) -> TimeInterval {
        guard let shown else {
            // Nothing on the notch, but the speakers are busy. Something is
            // probably playing that we have not caught yet, and this is the one
            // moment that must not be lazy.
            //
            // This was the "it takes five seconds to appear" bug. An empty
            // notch waited the full idle interval no matter what the machine
            // was doing, on the reasoning that silence has nothing to be stale
            // about — true of silence, and exactly wrong about a video that has
            // just started. The CoreAudio signal is supposed to catch the
            // start, and cannot be relied on here for the same reason it could
            // not be relied on for the paused case below: a browser holds its
            // audio session open between videos, so starting one does not
            // change whether the device is running and nothing fires.
            //
            // But "audio is running" does not prove a track exists to find. A
            // video call, a game, an alert sound — none of them publish a
            // now-playing session, and chasing those forever would spend a
            // subprocess every two seconds for the length of a meeting. So the
            // chase is bounded: look briskly a few times, and if nothing turns
            // up, accept that this sound has nothing behind it and go back to
            // sleep. The count resets when the sound stops, so the next thing
            // to start is chased just as promptly.
            guard audioElsewhere, fruitlessLooks < fruitlessLookLimit else { return idleInterval }
            return contendedInterval
        }
        if shown.isPlaying { return activeInterval }
        // Paused, but the speakers are busy: whatever is making that sound is
        // what should be on the notch, so look again shortly.
        return audioElsewhere ? contendedInterval : pausedInterval
    }

    /// What to tell the user when a command demonstrably did not take.
    ///
    /// Only the two causes worth acting on are named. If browser control is on
    /// AND Accessibility is granted, the keys really were pressed and something
    /// else refused them — there is nothing the user could usefully do about
    /// that, and a message they cannot act on is worse than silence. Pure and
    /// package-visible so the checks can pin it without a player or a
    /// permission.
    package nonisolated static func controlProblem(
        browserControlOn: Bool,
        accessibilityGranted: Bool
    ) -> ControlProblem? {
        guard browserControlOn else { return .browserControlOff }
        guard accessibilityGranted else { return .accessibilityMissing }
        return nil
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
