import SwiftUI
import HashNotchKit

/// Live internet throughput, shown to the left of the notch.
@MainActor
public final class NetworkFeature: NotchFeature {
    public let id = "network"
    public let title = "Network"
    public let placement: FeaturePlacement = .leading

    private let monitor = NetworkMonitor()

    public init() {}

    public func start() { monitor.start() }
    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        AnyView(NetworkView(monitor: monitor, theme: context.theme))
    }
}
