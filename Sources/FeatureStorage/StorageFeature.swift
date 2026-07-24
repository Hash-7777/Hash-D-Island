import SwiftUI
import HashDIslandKit

/// How full the startup disk is. Panel only — a disk fills over weeks, and
/// there is nothing about it worth a place beside the notch.
@MainActor
public final class StorageFeature: NotchFeature {
    public let id = "storage"
    public let title = "Storage"
    public let placement: FeaturePlacement = .expanded

    private let monitor = StorageMonitor()

    public init() {}

    public func start(context: FeatureContext) {
        monitor.start(
            visibility: context.visibility,
            scale: context.settings.samplingScale
        )
    }

    public func stop() { monitor.stop() }

    public func makeView(context: FeatureContext) -> AnyView { AnyView(EmptyView()) }

    public func makeExpandedView(context: FeatureContext) -> AnyView? {
        AnyView(StorageDetailView(monitor: monitor, theme: context.theme))
    }
}
