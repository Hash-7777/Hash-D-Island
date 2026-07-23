import SwiftUI
import HashDIslandKit

/// How the temperature readout is shown.
enum ThermalStyle: String {
    case symbolAndNumber
    case number
    case word
    case symbol
}

/// System temperature, shown to the right of the notch by default.
@MainActor
public final class ThermalFeature: NotchFeature {
    public let id = "thermal"
    public let title = "Temperature"
    public let placement: FeaturePlacement = .trailing

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: ThermalStyle.symbolAndNumber.rawValue, title: "Symbol and number"),
        FeatureOption(id: ThermalStyle.number.rawValue, title: "Number only"),
        FeatureOption(id: ThermalStyle.word.rawValue, title: "Word (Cool / Warm)"),
        FeatureOption(id: ThermalStyle.symbol.rawValue, title: "Symbol only"),
    ]

    private let monitor = ThermalMonitor()

    public init() {}

    public func start(context: FeatureContext) { monitor.start(visibility: context.visibility) }
    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        let style = ThermalStyle(rawValue: context.settings.style(for: id)) ?? .symbolAndNumber
        return AnyView(ThermalView(monitor: monitor, theme: context.theme, style: style))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(ThermalDetailView(monitor: monitor, theme: context.theme))
    }
}
