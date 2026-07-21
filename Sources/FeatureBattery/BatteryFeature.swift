import SwiftUI
import HashNotchKit

/// How the battery readout is shown.
enum BatteryStyle: String {
    case iconAndPercent
    case percent
    case icon
    case timeRemaining
}

/// Battery level and charging state.
@MainActor
public final class BatteryFeature: NotchFeature {
    public let id = "battery"
    public let title = "Battery"
    public let placement: FeaturePlacement = .trailing

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: BatteryStyle.iconAndPercent.rawValue, title: "Icon and percent"),
        FeatureOption(id: BatteryStyle.percent.rawValue, title: "Percent only"),
        FeatureOption(id: BatteryStyle.icon.rawValue, title: "Icon only"),
        FeatureOption(id: BatteryStyle.timeRemaining.rawValue, title: "Time remaining"),
    ]

    private let monitor = BatteryMonitor()

    public init() {}

    public func start() { monitor.start() }
    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        let style = BatteryStyle(rawValue: context.settings.style(for: id)) ?? .iconAndPercent
        return AnyView(BatteryView(monitor: monitor, theme: context.theme, style: style))
    }
}
