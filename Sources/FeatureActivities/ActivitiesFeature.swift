import SwiftUI
import HashNotchKit

/// Live activities posted by other apps / scripts / Shortcuts, shown like the
/// iPhone's Live Activities. Reads the local `~/.hashnotch/activities.json` feed.
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

    public func makeCompactLiveView(context: FeatureContext) -> AnyView? {
        AnyView(ActivitiesCompactView(monitor: monitor, theme: context.theme))
    }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(ActivitiesDetailView(monitor: monitor, theme: context.theme))
    }
}
