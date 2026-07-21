import Foundation
import SwiftUI
import HashNotchKit

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
/// Visibility rules (iPhone-like): the compact strip appears only while audio
/// is PLAYING; a paused Spotify/Music track keeps its card in the expanded
/// panel so it can be resumed; anything else disappears when it stops.
@MainActor
public final class MediaMonitor: ObservableObject {
    @Published public private(set) var nowPlaying: NowPlaying?
    @Published public private(set) var progress: MediaProgress?
    /// System output volume 0–100, shown as the panel's slider.
    @Published public private(set) var systemVolume: Int?

    private let reader = MediaRemoteReader()
    private var sampler: PollingSampler?
    private weak var presence: LivePresence?
    private var volumeWork: DispatchWorkItem?
    private var lastVolumeTouch = Date.distantPast

    public init() {}

    public func start(presence: LivePresence) {
        self.presence = presence
        // 2s keeps "media started → strip appears" latency low while staying
        // cheap (the fetch is out-of-process and skipped when one is running).
        sampler = PollingSampler(interval: 2.0) { [weak self] in self?.refresh() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        presence?.setActive("media", false)
    }

    // MARK: Controls

    public func togglePlayPause() {
        guard let media = nowPlaying else { return }
        // Optimistic flip so the button feels instant; the follow-up refresh
        // (and every poll after) corrects us if the player disagreed.
        setPlaying(!media.isPlaying)
        reader?.send(.playPause, to: media.source)
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

    /// Slider input: update instantly, push to the system coalesced so a drag
    /// becomes a handful of writes instead of hundreds.
    public func setVolume(_ volume: Int) {
        let clamped = min(max(volume, 0), 100)
        systemVolume = clamped
        lastVolumeTouch = Date()
        volumeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reader?.setSystemVolume(clamped) }
        }
        volumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
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
                volume: media.volume,
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
        presence?.setActive("media", playing)
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
        let shown: NowPlaying?
        if let snapshot, snapshot.isPlaying || snapshot.source != .other {
            shown = snapshot
        } else {
            shown = nil
        }

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

        // Adopt the polled system volume unless the user just moved the
        // slider — their hand wins over a stale sample.
        if let volume = snapshot?.volume,
           Date().timeIntervalSince(lastVolumeTouch) > 2,
           volume != systemVolume {
            systemVolume = volume
        }

        presence?.setActive("media", shown?.isPlaying == true)
    }
}
