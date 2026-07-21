import SwiftUI
import HashNotchKit

/// Battery level and charging state, shown to the right of the notch.
@MainActor
public final class BatteryFeature: NotchFeature {
    public let id = "battery"
    public let title = "Battery"
    public let placement: FeaturePlacement = .trailing

    private let monitor = BatteryMonitor()

    public init() {}

    public func start() { monitor.start() }
    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        AnyView(BatteryView(monitor: monitor, theme: context.theme))
    }
}
