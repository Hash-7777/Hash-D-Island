import SwiftUI
import HashDIslandKit

/// Live activities posted by other apps / scripts / Shortcuts, shown like the
/// iPhone's Live Activities. Reads the local `~/.hashdisland/activities.json` feed.
@MainActor
public final class ActivitiesFeature: NotchFeature {
    public let id = "activities"
    public let title = "Live activities"
    public let placement: FeaturePlacement = .leading

    private let monitor = ActivitiesMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(presence: context.presence)
    }

    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView {
        // Nothing in the hover row; activities live in the compact strip + detail.
        AnyView(EmptyView())
    }

    public func makeCompactLeadingView(context: FeatureContext) -> AnyView? {
        AnyView(ActivitiesIconView(monitor: monitor, theme: context.theme))
    }

    public func makeCompactTrailingView(context: FeatureContext) -> AnyView? {
        AnyView(ActivitiesTitleView(monitor: monitor, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        guard !monitor.activities.isEmpty else { return nil }
        return AnyView(ActivitiesDetailView(monitor: monitor, theme: context.theme))
    }
}
