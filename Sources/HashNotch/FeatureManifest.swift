import HashNotchKit
import FeatureNetwork
import FeatureBattery
import FeatureThermal
import FeatureTokens
import FeatureMedia
import FeatureActivities
import FeatureTimer

/// The one and only place features are turned on or off.
///
/// ── To ADD a feature ──────────────────────────────────────────────
///   1. Create `Sources/Feature<Name>/…` with a type conforming to
///      `NotchFeature`.
///   2. Add the target (and its dependency on this executable) in Package.swift.
///   3. `import Feature<Name>` above and add one line to the array below.
///
/// ── To REMOVE a feature ───────────────────────────────────────────
///   Delete its line below. (Optionally delete its module + Package.swift entry.)
///
/// The core (HashNotchKit) never changes for either.
enum FeatureManifest {
    @MainActor
    static func enabledFeatures() -> [NotchFeature] {
        [
            MediaFeature(),
            ActivitiesFeature(),
            TimerFeature(),
            TokensFeature(),
            NetworkFeature(),
            BatteryFeature(),
            ThermalFeature(),
        ]
    }
}
