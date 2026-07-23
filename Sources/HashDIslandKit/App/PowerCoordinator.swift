import AppKit

/// Pauses all feature sampling while the screen is asleep and resumes on wake.
///
/// Sampling nothing when nobody is looking is the single biggest battery win: no
/// timers fire, no work happens, until the display comes back. Combined with the
/// tolerant, coalesced timers in `PollingSampler`, the app's idle cost is
/// effectively nil.
@MainActor
public final class PowerCoordinator {
    private let registry: FeatureRegistry
    private let context: FeatureContext
    private var observers: [NSObjectProtocol] = []
    private var isPaused = false

    public init(registry: FeatureRegistry, context: FeatureContext) {
        self.registry = registry
        self.context = context
    }

    public func begin() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        })
    }

    public func end() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func pause() {
        guard !isPaused else { return }
        isPaused = true
        registry.stopAll()
    }

    private func resume() {
        guard isPaused else { return }
        isPaused = false
        registry.syncRunning(context: context)
    }
}
