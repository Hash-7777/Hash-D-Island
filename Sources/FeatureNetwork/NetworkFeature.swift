import SwiftUI
import HashDIslandKit

/// Which throughput directions the readout shows.
enum NetworkStyle: String {
    case both
    case downloadOnly
    case uploadOnly
}

/// Live internet throughput. Defaults to the left of the notch, keeping the
/// right side (battery, temperature) narrow and clear of the system status
/// icons. Users can move it to either side in Settings.
@MainActor
public final class NetworkFeature: NotchFeature {
    public let id = "network"
    public let title = "Internet speed"
    public let placement: FeaturePlacement = .leading

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: NetworkStyle.both.rawValue, title: "Up and down"),
        FeatureOption(id: NetworkStyle.downloadOnly.rawValue, title: "Download only"),
        FeatureOption(id: NetworkStyle.uploadOnly.rawValue, title: "Upload only"),
    ]

    private let monitor = NetworkMonitor()

    public init() {}

    public func start(context: FeatureContext) { monitor.start(visibility: context.visibility) }
    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        let style = NetworkStyle(rawValue: context.settings.style(for: id)) ?? .both
        return AnyView(NetworkView(monitor: monitor, theme: context.theme, style: style))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(NetworkDetailView(monitor: monitor, theme: context.theme))
    }
}
