import Foundation
import Combine

/// A sampler that runs only while the panel is open.
///
/// A readout that exists solely inside the panel has nothing to say while the
/// panel is shut, so this stops sampling entirely rather than computing values
/// nobody can see. It samples once the instant the panel opens, so the first
/// frame is already current rather than up to one interval stale, and it stops
/// again the moment the panel closes.
///
/// Features that also appear on the strip — media, the timer — need to keep
/// watching whether or not the panel is open, and use `PollingSampler` directly.
@MainActor
public final class VisibleSampler {
    private let interval: TimeInterval
    private let sample: () -> Void
    private let visibility: PanelVisibility
    private var sampler: PollingSampler?
    private var cancellable: AnyCancellable?

    public init(
        interval: TimeInterval,
        visibility: PanelVisibility,
        sample: @escaping () -> Void
    ) {
        self.interval = interval
        self.visibility = visibility
        self.sample = sample
    }

    public func start() {
        cancellable = visibility.$isOpen
            .removeDuplicates()
            .sink { [weak self] open in
                MainActor.assumeIsolated { self?.setRunning(open) }
            }
    }

    public func stop() {
        cancellable = nil
        setRunning(false)
    }

    private func setRunning(_ running: Bool) {
        guard running else {
            sampler?.stop()
            sampler = nil
            return
        }
        guard sampler == nil else { return }
        // PollingSampler fires once on start, which is exactly the behaviour
        // wanted here: the panel opens already showing a current value.
        let sampler = PollingSampler(interval: interval, tick: sample)
        self.sampler = sampler
        sampler.start()
    }
}
