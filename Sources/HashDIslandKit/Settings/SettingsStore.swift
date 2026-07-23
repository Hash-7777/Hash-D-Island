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

/// The whole persisted document. Unknown keys in an older saved document (e.g.
/// the removed layout block) are ignored on decode.
private struct SettingsDocument: Codable {
    var features: [String: FeatureConfig]
    var launchAtLogin: Bool
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

        if let document = Self.load(key: storageKey, from: defaults) {
            self.features = document.features
            self.launchAtLogin = document.launchAtLogin
            self.isFirstRun = false
        } else if let document = Self.loadLegacy(explicit: legacyDefaults, running: defaults) {
            // Carried over from the previous name, once. It is written back
            // under the new key by the save below, so this path is not taken
            // again.
            self.features = document.features
            self.launchAtLogin = document.launchAtLogin
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

    /// Force an immediate synchronous save (the automatic save is coalesced to
    /// the next runloop tick; tests and shutdown use this).
    public func flush() { save() }

    private func save() {
        let document = SettingsDocument(
            features: features,
            launchAtLogin: launchAtLogin
        )
        if let data = try? JSONEncoder().encode(document) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
