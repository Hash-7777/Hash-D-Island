import Foundation
import SwiftUI
import HashDIslandKit

/// Watches the activity feed and keeps a live `now` clock so countdowns tick.
///
/// Nothing here runs on a schedule unless it has to. The feed is watched rather
/// than polled, the clock runs only while a countdown is actually on screen,
/// and a notice is dismissed by a single timer set for the exact moment it is
/// due. With nothing posted, this costs nothing.
@MainActor
public final class ActivitiesMonitor: ObservableObject {
    @Published public private(set) var activities: [LiveActivity] = []
    @Published public private(set) var now: Date = Date()

    private var watcher: DirectoryWatcher?
    private var sampler: PollingSampler?
    private var clock: PollingSampler?
    private weak var presence: LivePresence?

    /// When each self-dismissing notice was first seen. A notice says how long
    /// it wants to be shown for, not when it should go: the writer has no idea
    /// when the app will next look at the file.
    private var firstSeen: [String: Date] = [:]
    private var dismissalWork: DispatchWorkItem?

    public init() {}

    /// How long a notice stays, and whether a request waits. The poster
    /// suggests a duration; this is the reader's preference, and the reader
    /// wins — it is your notch.
    private weak var settings: SettingsStore?

    public func start(presence: LivePresence, settings: SettingsStore? = nil) {
        self.presence = presence
        self.settings = settings
        reload()

        // The feed changes when somebody posts, which is rarely and never on a
        // schedule. Watch the folder rather than stat-ing the file forever —
        // the folder, not the file, because the file is replaced by a rename
        // and a file-level watch would go deaf after the first post.
        watcher = DirectoryWatcher(url: ActivitiesReader.feedURL.deletingLastPathComponent()) {
            [weak self] in self?.reload()
        }
        if watcher == nil {
            // The folder does not exist yet, so nothing has ever posted. Look
            // for it occasionally, and switch to watching once it appears.
            sampler = PollingSampler(interval: 3.0) { [weak self] in self?.lookForFolder() }
            sampler?.start()
        }
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
        sampler?.stop()
        sampler = nil
        clock?.stop()
        clock = nil
        dismissalWork?.cancel()
        dismissalWork = nil
        firstSeen.removeAll()
        presence?.setActive("activities", false)
    }

    /// Nothing has ever posted. As soon as the folder exists, start watching it
    /// and stop looking.
    private func lookForFolder() {
        let folder = ActivitiesReader.feedURL.deletingLastPathComponent()
        guard let watcher = DirectoryWatcher(url: folder, onChange: { [weak self] in
            self?.reload()
        }) else { return }

        self.watcher = watcher
        sampler?.stop()
        sampler = nil
        reload()
    }

    private func reload() {
        apply(ActivitiesReader.read())
    }

    private func apply(_ fresh: [LiveActivity]) {
        let moment = Date()

        // Remember when each notice arrived, and forget the ones that have gone.
        let ids = Set(fresh.map(\.id))
        firstSeen = firstSeen.filter { ids.contains($0.key) }
        for activity in fresh where activity.dismissAfter != nil && firstSeen[activity.id] == nil {
            firstSeen[activity.id] = moment
        }

        let preferred = settings?.alerts.noticeSeconds
        let showing = fresh.filter { activity in
            guard !activity.isExpired else { return false }
            guard let seen = firstSeen[activity.id],
                  let dismissal = activity.dismissalDate(firstSeen: seen, preferring: preferred)
            else { return true }
            return dismissal > moment
        }

        if showing != activities { activities = showing }
        presence?.setActive("activities", !activities.isEmpty)
        scheduleNextDismissal(from: moment)
        updateClock()
    }

    /// The one-second clock exists only to move countdown digits. A notice
    /// draws no timer, and an empty island needs no clock at all.
    private func updateClock() {
        let needsClock = activities.contains(where: \.showsCountdown)
        if needsClock, clock == nil {
            now = Date()
            let clock = PollingSampler(interval: 1.0) { [weak self] in
                guard let self else { return }
                self.now = Date()
                // A countdown reaching its end is the one thing the file watch
                // will never announce, so re-evaluate as it ticks.
                self.apply(ActivitiesReader.read())
            }
            self.clock = clock
            clock.start()
        } else if !needsClock, clock != nil {
            clock?.stop()
            clock = nil
        }
    }

    /// Wake exactly once, when the soonest notice is due to leave — something
    /// measured in seconds cannot wait for a tick that may not be running.
    private func scheduleNextDismissal(from moment: Date) {
        dismissalWork?.cancel()
        dismissalWork = nil

        let preferred = settings?.alerts.noticeSeconds
        let due = activities.compactMap { activity -> Date? in
            guard let seen = firstSeen[activity.id] else { return nil }
            return activity.dismissalDate(firstSeen: seen, preferring: preferred)
        }
        guard let soonest = due.min() else { return }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        dismissalWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.05, soonest.timeIntervalSince(moment)),
            execute: work
        )
    }
}
