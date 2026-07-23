import Foundation
import SwiftUI
import HashDIslandKit

/// Watches the activity feed file and keeps a live `now` clock so countdowns
/// tick. Only re-reads the file when it changes; only publishes the clock while
/// activities are present, so it costs nothing when idle.
@MainActor
public final class ActivitiesMonitor: ObservableObject {
    @Published public private(set) var activities: [LiveActivity] = []
    @Published public private(set) var now: Date = Date()

    private var sampler: PollingSampler?
    private var lastModified: Date?
    private weak var presence: LivePresence?

    public init() {}

    public func start(presence: LivePresence) {
        self.presence = presence
        reload(force: true)
        sampler = PollingSampler(interval: 1.0) { [weak self] in self?.tick() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        presence?.setActive("activities", false)
    }

    private func tick() {
        reload(force: false)
        // Keep countdowns moving only while something is showing.
        if !activities.isEmpty {
            now = Date()
        }
    }

    private func reload(force: Bool) {
        let modified = (try? ActivitiesReader.feedURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate

        if force || modified != lastModified {
            lastModified = modified
            let fresh = ActivitiesReader.read()
            if fresh != activities { activities = fresh }
        } else {
            // File unchanged, but an activity may have just expired.
            let stillActive = activities.filter { !$0.isExpired }
            if stillActive != activities { activities = stillActive }
        }

        presence?.setActive("activities", !activities.isEmpty)
    }
}
