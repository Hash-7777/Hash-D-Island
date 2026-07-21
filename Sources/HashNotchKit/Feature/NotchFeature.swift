import SwiftUI

/// Where a feature is placed in the notch HUD.
public enum FeaturePlacement: Sendable, CaseIterable {
    /// Compact readout to the left of the physical notch.
    case leading
    /// Compact readout to the right of the physical notch.
    case trailing
    /// Shown only in the expanded panel below the notch.
    case expanded
}

/// The single contract every feature implements.
///
/// A feature is a self-contained unit: it owns its own data source and its own
/// SwiftUI view. The core never imports a feature and never knows what any
/// feature does — it only sees this protocol. That is what lets features be
/// added or removed without touching core code.
@MainActor
public protocol NotchFeature: AnyObject {
    /// Stable, unique identifier (used for layout identity and settings).
    var id: String { get }

    /// Human-readable name, shown in the expanded panel and settings.
    var title: String { get }

    /// Where this feature renders in the HUD.
    var placement: FeaturePlacement { get }

    /// Build the compact SwiftUI view shown around the notch. Main actor.
    func makeView(context: FeatureContext) -> AnyView

    /// Optional richer view shown in the expanded panel when the HUD opens on
    /// hover. Return `nil` (the default) to show nothing extra when expanded.
    func makeExpandedView(context: FeatureContext) -> AnyView?

    /// Begin sampling / observing. Called once when the HUD starts.
    func start()

    /// Stop sampling / observing and release resources.
    func stop()
}

public extension NotchFeature {
    func makeExpandedView(context: FeatureContext) -> AnyView? { nil }
    func start() {}
    func stop() {}
}
