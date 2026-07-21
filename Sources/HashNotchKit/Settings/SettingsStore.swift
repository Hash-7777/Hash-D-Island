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

/// Saved layout tuning so the HUD can be nudged clear of the menu bar's app
/// menus (left) and status items (right).
public struct LayoutConfig: Codable, Equatable {
    /// Extra gap (points) between the left content and the notch.
    public var leadingInset: Double
    /// Extra gap (points) between the right content and the notch.
    public var trailingInset: Double
    /// Space between individual readouts.
    public var itemSpacing: Double

    public static let `default` = LayoutConfig(leadingInset: 8, trailingInset: 8, itemSpacing: 12)
}

/// The whole persisted document.
private struct SettingsDocument: Codable {
    var features: [String: FeatureConfig]
    var layout: LayoutConfig
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
    @Published public var layout: LayoutConfig
    @Published public var launchAtLogin: Bool

    /// True when there was no saved configuration to load (i.e. first ever run).
    /// Used to show the settings window once so the app is easy to find.
    public let isFirstRun: Bool

    private let defaults: UserDefaults
    private let storageKey = "hashnotch.settings.v2"
    private var saveCancellable: AnyCancellable?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
           let document = try? JSONDecoder().decode(SettingsDocument.self, from: data) {
            self.features = document.features
            self.layout = document.layout
            self.launchAtLogin = document.launchAtLogin
            self.isFirstRun = false
        } else {
            self.features = [:]
            self.layout = .default
            self.launchAtLogin = false
            self.isFirstRun = true
        }

        // Persist on any change, coalesced to the next runloop tick.
        saveCancellable = objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.save() }
            }
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
            layout: layout,
            launchAtLogin: launchAtLogin
        )
        if let data = try? JSONEncoder().encode(document) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
