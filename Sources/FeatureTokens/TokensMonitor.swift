import Foundation
import SwiftUI
import HashDIslandKit

/// Publishes today's AI token usage, refreshed on a light interval. The file
/// scan runs on a background queue so the HUD never stutters; results are
/// published on the main actor inside an animation so the numbers roll smoothly.
@MainActor
public final class TokensMonitor: ObservableObject {
    @Published public private(set) var today = TokenTotals()

    private var sampler: PollingSampler?
    private let queue = DispatchQueue(label: "com.hashdisland.tokens", qos: .utility)

    public init() {}

    public func start() {
        sampler = PollingSampler(interval: 30.0) { [weak self] in self?.refresh() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
    }

    private func refresh() {
        queue.async { [weak self] in
            let totals = TokenUsageReader.readToday()
            Task { @MainActor in
                guard let self, totals != self.today else { return }
                withAnimation(.snappy) { self.today = totals }
            }
        }
    }
}
