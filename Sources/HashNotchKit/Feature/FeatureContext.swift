import Foundation

/// Shared services handed to every feature when it builds its view.
///
/// This is how the core passes common things (theme, user settings) to features
/// without any feature depending on another. Extend this type to share more —
/// features opt in by reading what they need.
@MainActor
public final class FeatureContext {
    public let theme: Theme
    public let settings: SettingsStore

    public init(theme: Theme = .default, settings: SettingsStore) {
        self.theme = theme
        self.settings = settings
    }
}
