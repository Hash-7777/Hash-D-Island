import Foundation
import SwiftUI
import HashNotchKit

/// Publishes the current Now Playing track and signals live presence while media
/// is present. Polls on a light interval; the MediaRemote fetch is async and
/// returns on a background queue, so results hop to the main actor to publish.
@MainActor
public final class MediaMonitor: ObservableObject {
    @Published public private(set) var nowPlaying: NowPlaying?

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

    private func refresh() {
        guard let reader else { return }
        reader.fetch { snapshot in
            Task { @MainActor [weak self] in self?.apply(snapshot) }
        }
    }

    private func apply(_ snapshot: NowPlaying?) {
        if snapshot != nowPlaying {
            withAnimation(.snappy) { nowPlaying = snapshot }
        }
        presence?.setActive("media", snapshot != nil)
    }
}
