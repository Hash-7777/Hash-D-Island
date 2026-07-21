import SwiftUI
import HashNotchKit

/// System thermal pressure, shown to the right of the notch.
@MainActor
public final class ThermalFeature: NotchFeature {
    public let id = "thermal"
    public let title = "Temperature"
    public let placement: FeaturePlacement = .trailing

    private let monitor = ThermalMonitor()

    public init() {}

    public func start() { monitor.start() }
    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        AnyView(ThermalView(monitor: monitor, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(ThermalDetailView(monitor: monitor, theme: context.theme))
    }
}
