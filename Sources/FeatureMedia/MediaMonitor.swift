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

    private let reader = MediaRemoteReader()
    private var sampler: PollingSampler?
    private weak var presence: LivePresence?

    public init() {}

    public func start(presence: LivePresence) {
        self.presence = presence
        sampler = PollingSampler(interval: 3.0) { [weak self] in self?.refresh() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        presence?.setActive("media", false)
    }

    // MARK: Controls

    public func togglePlayPause() {
        guard let media = nowPlaying, media.source != .other else { return }
        // Optimistic flip so the button feels instant; the follow-up refresh
        // (and every poll after) corrects us if the player disagreed.
        setPlaying(!media.isPlaying)
        reader?.send(.playPause, to: media.source)
        scheduleRefresh()
    }

    public func next() {
        guard let media = nowPlaying, media.source != .other else { return }
        reader?.send(.next, to: media.source)
        scheduleRefresh()
    }

    public func previous() {
        guard let media = nowPlaying, media.source != .other else { return }
        reader?.send(.previous, to: media.source)
        scheduleRefresh()
    }

    private func setPlaying(_ playing: Bool) {
        guard let media = nowPlaying else { return }
        let now = Date()
        withAnimation(.snappy) {
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
            withAnimation(.snappy) { nowPlaying = shown }
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

        presence?.setActive("media", shown?.isPlaying == true)
    }
}
