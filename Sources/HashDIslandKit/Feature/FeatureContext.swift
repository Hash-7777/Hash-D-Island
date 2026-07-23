import Foundation

/// Shared services handed to every feature when it builds its view.
///
/// This is how the core passes common things (theme, user settings, live
/// presence) to features without any feature depending on another. Extend this
/// type to share more — features opt in by reading what they need.
@MainActor
public final class FeatureContext {
    /// Visual tokens, re-derived from settings each time they are asked for, so
    /// a change of accent reaches every feature without any of them subscribing
    /// to anything.
    public var theme: Theme { baseTheme.tinted(settings.accent.color) }

    private let baseTheme: Theme
    public let settings: SettingsStore
    public let presence: LivePresence
    /// Whether the panel is open. Features that only draw inside it sample
    /// against this instead of running around the clock.
    public let visibility: PanelVisibility

    /// Opens the customization window. The app wires this at launch; the
    /// island's gear button calls it (there is no menu-bar item).
    public var openSettings: () -> Void = {}

    public init(
        theme: Theme = .default,
        settings: SettingsStore,
        presence: LivePresence? = nil,
        visibility: PanelVisibility? = nil
    ) {
        self.baseTheme = theme
        self.settings = settings
        self.presence = presence ?? LivePresence()
        self.visibility = visibility ?? PanelVisibility()
    }
}
