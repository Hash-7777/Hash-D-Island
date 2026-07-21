import SwiftUI
import HashNotchKit

/// System-wide Now Playing media (music, video), shown in the notch like the
/// iPhone's Dynamic Island.
@MainActor
public final class MediaFeature: NotchFeature {
    public let id = "media"
    public let title = "Now playing"
    public let placement: FeaturePlacement = .leading

    private let monitor = MediaMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(presence: context.presence)
    }

    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        // Media shows flanking the notch and in the expanded detail only.
        AnyView(EmptyView())
    }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(MediaArtworkView(monitor: monitor, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(MediaTitleView(monitor: monitor, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(MediaDetailView(monitor: monitor, theme: context.theme))
    }
}
