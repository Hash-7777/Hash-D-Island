import Foundation

/// Holds the set of enabled features and hands them to the HUD.
///
/// The registry is the seam between "which features exist" (decided once, in the
/// app's FeatureManifest) and "how features are laid out and driven" (the core).
/// Nothing here knows any concrete feature type.
@MainActor
public final class FeatureRegistry {
    public private(set) var features: [NotchFeature] = []

    /// Which features are actually running. Tracked so a settings change can
    /// start or stop the one that changed without disturbing the others.
    private var running: Set<String> = []

    public init() {}

    public func register(_ feature: NotchFeature) {
        features.append(feature)
        orderedCache = nil
    }

    public func register(_ newFeatures: [NotchFeature]) {
        features.append(contentsOf: newFeatures)
        orderedCache = nil
    }

    /// Features assigned to a given placement, in registration order.
    public func features(for placement: FeaturePlacement) -> [NotchFeature] {
        features.filter { $0.placement == placement }
    }

    /// The enabled features, in the order they should be drawn.
    ///
    /// Cached against `SettingsStore.featuresGeneration`, because the island
    /// asks for this while it is drawing and the answer can only change when a
    /// setting does. The island's body re-evaluates on every published change
    /// from every monitor — a token total, a CPU sample, each frame of an
    /// opening spring — and each of those was previously paying for a map, a
    /// filter, a sort and eleven config lookups to arrive at the same list it
    /// had a moment earlier.
    ///
    /// Ties break on id. Two features can only share an `order` if a saved
    /// document predates `seed`, and `Array.sorted` is not a stable sort, so
    /// without this the pair could swap places between one redraw and the next.
    public func orderedEnabled(using settings: SettingsStore) -> [NotchFeature] {
        if let cache = orderedCache, cache.generation == settings.featuresGeneration {
            return cache.value
        }
        // Written as explicit steps rather than one chain: the fused
        // map/filter/sort/map defeated the type checker outright.
        var ranked: [(feature: NotchFeature, order: Int)] = []
        ranked.reserveCapacity(features.count)
        for (index, feature) in features.enumerated() {
            let config = settings.config(for: feature, index: index)
            guard config.enabled else { continue }
            ranked.append((feature, config.order))
        }
        ranked.sort { left, right in
            left.order == right.order
                ? left.feature.id < right.feature.id
                : left.order < right.order
        }
        let value = ranked.map(\.feature)
        orderedCache = (settings.featuresGeneration, value)
        return value
    }

    private var orderedCache: (generation: Int, value: [NotchFeature])?

    /// Bring what is running in line with what the user has switched on: start
    /// every enabled feature that is not running, stop every disabled one that
    /// is.
    ///
    /// A feature that is switched off is stopped, not merely hidden. Hiding it
    /// while its monitor carried on would mean turning Downloads off still
    /// listed the folder, turning AirPods off still asked the system about
    /// Bluetooth, and turning Now Playing off still asked Spotify, Music, and
    /// the browsers for what they were doing — permission prompts and all.
    /// Nobody means "keep doing it, just don't tell me" when they turn
    /// something off, and an app that reads what it has been asked to stop
    /// reading cannot claim to be verifiable by reading its source.
    ///
    /// Idempotent, so it is safe to call on every settings change: a feature
    /// already in the right state is left alone rather than restarted.
    public func syncRunning(context: FeatureContext) {
        for feature in features {
            let wanted = context.settings.isEnabled(feature.id)
            if wanted, !running.contains(feature.id) {
                feature.start(context: context)
                running.insert(feature.id)
            } else if !wanted, running.contains(feature.id) {
                feature.stop()
                running.remove(feature.id)
            }
        }
    }

    public func stopAll() {
        features.forEach { $0.stop() }
        running.removeAll()
    }

    /// The ids of the features currently running. Package-visible so the checks
    /// can prove that switching one off actually stops it.
    package var runningIDs: Set<String> { running }
}
