import Foundation
import SwiftUI
import HashDIslandKit

/// Watches the activity feed file and keeps a live `now` clock so countdowns
/// tick. Only re-reads the file when it changes; only publishes the clock while
/// a countdown is actually on screen, so it costs nothing when idle.
@MainActor
public final class ActivitiesMonitor: ObservableObject {
    @Published public private(set) var activities: [LiveActivity] = []
    @Published public private(set) var now: Date = Date()

    private var sampler: PollingSampler?
    private var lastModified: Date?
    private weak var presence: LivePresence?

    /// When each self-dismissing notice was first seen. A notice says how long
    /// it wants to be shown for, not when it should go — the writer has no idea
    /// when the app will next look at the file, and an absolute deadline would
    /// make a notice posted while the Mac was asleep arrive already expired.
    private var firstSeen: [String: Date] = [:]
    private var dismissalWork: DispatchWorkItem?

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
        dismissalWork?.cancel()
        dismissalWork = nil
        firstSeen.removeAll()
        presence?.setActive("activities", false)
    }

    private func tick() {
        reload(force: false)
        // Keep the clock moving only while a countdown is on screen. A notice
        // draws no timer, so it needs no clock.
        if activities.contains(where: \.showsCountdown) {
            now = Date()
        }
    }

    private func reload(force: Bool) {
        let modified = (try? ActivitiesReader.feedURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate

        if force || modified != lastModified {
            lastModified = modified
            apply(ActivitiesReader.read())
        } else {
            // File unchanged, but something may have just run out.
            apply(activities)
        }

        presence?.setActive("activities", !activities.isEmpty)
    }

    private func apply(_ fresh: [LiveActivity]) {
        let moment = Date()

        // Remember when each notice arrived, and forget the ones that have gone.
        let ids = Set(fresh.map(\.id))
        firstSeen = firstSeen.filter { ids.contains($0.key) }
        for activity in fresh where activity.dismissAfter != nil && firstSeen[activity.id] == nil {
            firstSeen[activity.id] = moment
        }

        let showing = fresh.filter { activity in
            guard !activity.isExpired else { return false }
            guard let seen = firstSeen[activity.id],
                  let dismissal = activity.dismissalDate(firstSeen: seen) else { return true }
            return dismissal > moment
        }

        if showing != activities { activities = showing }
        scheduleNextDismissal(from: moment)
    }

    /// Wake exactly once, when the soonest notice is due to leave — a notice
    /// measured in seconds cannot wait for the next one-second tick to notice
    /// it has outstayed its welcome.
    private func scheduleNextDismissal(from moment: Date) {
        dismissalWork?.cancel()
        dismissalWork = nil

        let due = activities.compactMap { activity -> Date? in
            guard let seen = firstSeen[activity.id] else { return nil }
            return activity.dismissalDate(firstSeen: seen)
        }
        guard let soonest = due.min() else { return }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload(force: false) }
        }
        dismissalWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.05, soonest.timeIntervalSince(moment)),
            execute: work
        )
    }
}
