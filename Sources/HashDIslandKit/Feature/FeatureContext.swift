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

    /// Opens the customization window ON a particular page.
    ///
    /// For the case where the island has just told somebody that a switch is
    /// off. Sending them to a window and leaving them to find it themselves is
    /// most of the way to not having told them.
    public var openSettingsPage: (String) -> Void = { _ in }

    /// Shuts the panel. For the case where a feature is about to hand the user
    /// over to something else — a system permission dialog, say — and the panel
    /// would otherwise sit on top of the thing it just asked them to look at.
    ///
    /// A closure, like `openSettings`, rather than a method on
    /// `PanelVisibility`: that type reports whether anyone is looking, and a
    /// feature reaching in to change it would make an observation into a
    /// control that the island does not know was used.
    public var closePanel: () -> Void = {}

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
