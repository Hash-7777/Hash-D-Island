import Foundation
import Combine

/// Saved configuration for one feature.
public struct FeatureConfig: Codable, Equatable {
    public var enabled: Bool
    public var placement: FeaturePlacement
    public var styleID: String
    public var order: Int

    public init(enabled: Bool, placement: FeaturePlacement, styleID: String, order: Int) {
        self.enabled = enabled
        self.placement = placement
        self.styleID = styleID
        self.order = order
    }
}

/// How the island looks. Every value here is wired to something visible — a
/// setting that changed nothing would be worse than no setting at all.
public struct AppearanceSettings: Codable, Equatable {
    /// The open panel's fill. The resting notch and the live strip are always
    /// solid black so they read as one piece with the hardware.
    public enum PanelFill: String, Codable, CaseIterable, Sendable {
        case glass
        case solid

        public var label: String {
            switch self {
            case .glass: return "Frosted glass"
            case .solid: return "Solid black"
            }
        }
    }

    /// How eager the island's motion is.
    public enum Motion: String, Codable, CaseIterable, Sendable {
        case calm
        case standard
        case lively

        public var label: String {
            switch self {
            case .calm: return "Calm"
            case .standard: return "Standard"
            case .lively: return "Lively"
            }
        }

        /// Multiplies every spring's response. Higher is slower and softer.
        public var responseScale: Double {
            switch self {
            case .calm: return 1.35
            case .standard: return 1.0
            case .lively: return 0.72
            }
        }
    }

    public var panelFill: PanelFill = .glass
    public var accentID: String = AccentColor.default.id
    public var motion: Motion = .standard
    /// The open panel's corner rounding, in points.
    public var panelCornerRadius: Double = 26

    public init() {}
}

/// How alerts behave.
public struct AlertSettings: Codable, Equatable {
    /// How long a "something finished" notice stays on the notch. The poster
    /// suggests a duration; this is the reader's preference, and the reader
    /// wins — it is your notch.
    public var noticeSeconds: Double = 3
    /// Whether an alert that is asking for something — a permission prompt —
    /// waits for you instead of leaving on its own.
    public var requestsWaitForYou: Bool = true

    public init() {}
}

/// The whole persisted document. Unknown keys in an older saved document (e.g.
/// the removed layout block) are ignored on decode, and missing ones fall back
/// to their defaults, so a document written by an older build still loads.
private struct SettingsDocument: Codable {
    var features: [String: FeatureConfig]
    var launchAtLogin: Bool
    var batterySaver: Bool?
    var appearance: AppearanceSettings?
    var alerts: AlertSettings?
}

/// The single source of truth for user customization, backed by `UserDefaults`.
///
/// Features and the HUD read from here; the settings window writes to it. Any
/// change is saved automatically. The store is intentionally the only stateful
/// place — features stay stateless about configuration.
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var features: [String: FeatureConfig]
    @Published public var launchAtLogin: Bool
    /// Halves how often everything samples. Features re-read this when they
    /// restart, which the app does as soon as it changes.
    @Published public var batterySaver: Bool = false
    @Published public var appearance = AppearanceSettings()
    @Published public var alerts = AlertSettings()

    /// Multiplies every sampling interval. Kept here rather than in each
    /// monitor so "sample less often" means one number in one place.
    public var samplingScale: Double { batterySaver ? 2 : 1 }

    /// The accent colour, resolved from the stored id.
    public var accent: AccentColor { AccentColor.named(appearance.accentID) }

    /// True when there was no saved configuration to load (i.e. first ever run).
    /// Used to show the settings window once so the app is easy to find.
    public let isFirstRun: Bool

    private let defaults: UserDefaults
    private let storageKey = "hashdisland.settings.v2"
    private var saveCancellable: AnyCancellable?

    /// Where settings lived before the app was renamed. Preferences are keyed by
    /// bundle identifier, so without this an existing install would silently
    /// come back with every choice reset.
    private static let legacyKey = "hashnotch.settings.v2"
    private static let legacyDomain = "com.hashnotch.app"

    /// `legacyDefaults` is where settings written under the app's previous name
    /// are looked for. It is a parameter purely so the checks can prove the
    /// carry-over works without touching the real preferences.
    public init(defaults: UserDefaults = .standard, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults

        // Carried-over settings come from the app's previous name and are
        // written back under the new key by the save below, so that path is
        // taken exactly once.
        let document = Self.load(key: storageKey, from: defaults)
            ?? Self.loadLegacy(explicit: legacyDefaults, running: defaults)

        if let document {
            self.features = document.features
            self.launchAtLogin = document.launchAtLogin
            self.batterySaver = document.batterySaver ?? false
            self.appearance = document.appearance ?? AppearanceSettings()
            self.alerts = document.alerts ?? AlertSettings()
            self.isFirstRun = false
        } else {
            self.features = [:]
            self.launchAtLogin = false
            self.isFirstRun = true
        }

        // Persist on any change, coalesced to the next runloop tick.
        saveCancellable = objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.save() }
            }

        // Write the carried-over settings straight away, so they survive even
        // if the app is quit before anything else changes.
        if !isFirstRun, defaults.data(forKey: storageKey) == nil { save() }
    }

    private static func load(key: String, from defaults: UserDefaults) -> SettingsDocument? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SettingsDocument.self, from: data)
    }

    /// Settings saved under the app's previous name. Checked in the running
    /// defaults first (an unbundled `swift run` build shares one domain), then
    /// in the old bundle's own domain, which is where a real installed copy
    /// kept them.
    private static func loadLegacy(
        explicit: UserDefaults?,
        running: UserDefaults
    ) -> SettingsDocument? {
        if let explicit { return load(key: legacyKey, from: explicit) }
        if let document = load(key: legacyKey, from: running) { return document }
        guard let legacy = UserDefaults(suiteName: legacyDomain) else { return nil }
        return load(key: legacyKey, from: legacy)
    }

    // MARK: Reading

    /// The stored config for a feature, or a sensible default derived from the
    /// feature itself the first time it is seen.
    public func config(for feature: NotchFeature, index: Int) -> FeatureConfig {
        if let stored = features[feature.id] { return stored }
        return FeatureConfig(
            enabled: true,
            placement: feature.placement,
            styleID: feature.displayOptions.first?.id ?? "default",
            order: index
        )
    }

    public func isEnabled(_ id: String) -> Bool {
        features[id]?.enabled ?? true
    }

    public func style(for id: String) -> String {
        features[id]?.styleID ?? "default"
    }

    // MARK: Writing

    /// Ensure every known feature has a stored config (called once at launch so
    /// the settings UI has something to bind to).
    public func seed(features list: [NotchFeature]) {
        for (index, feature) in list.enumerated() where features[feature.id] == nil {
            features[feature.id] = config(for: feature, index: index)
        }
    }

    public func update(_ id: String, _ mutate: (inout FeatureConfig) -> Void) {
        guard var config = features[id] else { return }
        mutate(&config)
        features[id] = config
    }

    /// Rewrite the display order from a list of ids, top to bottom.
    ///
    /// Order is stored per feature rather than as a list so that a feature
    /// added in a later version simply appears at its default position instead
    /// of being lost from a saved list that predates it.
    public func setOrder(_ ids: [String]) {
        for (index, id) in ids.enumerated() {
            update(id) { $0.order = index }
        }
    }

    /// Enabled features, in the order they should be drawn.
    ///
    /// Ties break on id so the order is stable rather than dependent on
    /// dictionary iteration, which would otherwise let two features swap places
    /// between launches.
    public func orderedIDs(among list: [NotchFeature]) -> [String] {
        var ranked: [(id: String, order: Int)] = []
        for (index, feature) in list.enumerated() {
            ranked.append((feature.id, config(for: feature, index: index).order))
        }
        ranked.sort { left, right in
            left.order == right.order ? left.id < right.id : left.order < right.order
        }
        return ranked.map(\.id)
    }

    /// Force an immediate synchronous save (the automatic save is coalesced to
    /// the next runloop tick; tests and shutdown use this).
    public func flush() { save() }

    private func save() {
        let document = SettingsDocument(
            features: features,
            launchAtLogin: launchAtLogin,
            batterySaver: batterySaver,
            appearance: appearance,
            alerts: alerts
        )
        if let data = try? JSONEncoder().encode(document) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
