import SwiftUI
import HashNotchKit

/// Which throughput directions the readout shows.
enum NetworkStyle: String {
    case both
    case downloadOnly
    case uploadOnly
}

/// Live internet throughput. Defaults to the right of the notch so it never
/// collides with the frontmost app's menus on the left.
@MainActor
public final class NetworkFeature: NotchFeature {
    public let id = "network"
    public let title = "Internet speed"
    public let placement: FeaturePlacement = .trailing

    public let displayOptions: [FeatureOption] = [
        FeatureOption(id: NetworkStyle.both.rawValue, title: "Up and down"),
        FeatureOption(id: NetworkStyle.downloadOnly.rawValue, title: "Download only"),
        FeatureOption(id: NetworkStyle.uploadOnly.rawValue, title: "Upload only"),
    ]

    private let monitor = NetworkMonitor()

    public init() {}

    public func start() { monitor.start() }
    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        let style = NetworkStyle(rawValue: context.settings.style(for: id)) ?? .both
        return AnyView(NetworkView(monitor: monitor, theme: context.theme, style: style))
    }
}
