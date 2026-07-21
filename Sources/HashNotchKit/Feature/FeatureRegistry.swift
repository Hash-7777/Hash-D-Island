import Foundation

/// Holds the set of enabled features and hands them to the HUD.
///
/// The registry is the seam between "which features exist" (decided once, in the
/// app's FeatureManifest) and "how features are laid out and driven" (the core).
/// Nothing here knows any concrete feature type.
@MainActor
public final class FeatureRegistry {
    public private(set) var features: [NotchFeature] = []

    public init() {}

    public func register(_ feature: NotchFeature) {
        features.append(feature)
    }

    public func register(_ newFeatures: [NotchFeature]) {
        features.append(contentsOf: newFeatures)
    }

    /// Features assigned to a given placement, in registration order.
    public func features(for placement: FeaturePlacement) -> [NotchFeature] {
        features.filter { $0.placement == placement }
    }

    public func startAll() {
        features.forEach { $0.start() }
    }

    public func stopAll() {
        features.forEach { $0.stop() }
    }
}
