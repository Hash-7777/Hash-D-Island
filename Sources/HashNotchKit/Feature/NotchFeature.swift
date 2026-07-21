import SwiftUI

/// Where a feature is placed in the notch HUD.
public enum FeaturePlacement: String, Sendable, CaseIterable, Codable {
    /// Compact readout to the left of the physical notch.
    case leading
    /// Compact readout to the right of the physical notch.
    case trailing
    /// Shown only in the expanded panel below the notch.
    case expanded

    /// Friendly label for the settings UI.
    public var label: String {
        switch self {
        case .leading: return "Left of notch"
        case .trailing: return "Right of notch"
        case .expanded: return "Expanded only"
        }
    }
}

/// One selectable way a feature can display itself (e.g. number vs. word vs.
/// symbol). Features declare their options; the settings UI lists them and the
/// feature's view reads the chosen one from `FeatureContext`.
public struct FeatureOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
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

    /// Default placement when the user has not chosen one. The live placement
    /// comes from settings, so the user can move features left or right.
    var placement: FeaturePlacement { get }

    /// The display styles this feature offers (e.g. number / word / symbol).
    /// The first is the default. Return `[]` for a feature with no choices.
    var displayOptions: [FeatureOption] { get }

    /// Build the compact SwiftUI view shown around the notch. Main actor.
    /// Read the chosen style from `context.settings.style(for: id)`.
    func makeView(context: FeatureContext) -> AnyView

    /// Optional richer view shown in the expanded panel when the HUD opens on
    /// hover. Return `nil` (the default) to show nothing extra when expanded.
    func makeExpandedView(context: FeatureContext) -> AnyView?

    /// Optional always-on view shown in the slim strip below the notch while
    /// something is live (media playing, an activity running) — like the
    /// iPhone's compact Dynamic Island. Return `nil` (the default) for none.
    func makeCompactLiveView(context: FeatureContext) -> AnyView?

    /// Begin sampling / observing. Called when the HUD starts. The context gives
    /// access to shared services (e.g. `presence` for signalling live content).
    func start(context: FeatureContext)

    /// Stop sampling / observing and release resources.
    func stop()
}

public extension NotchFeature {
    var displayOptions: [FeatureOption] { [] }
    func makeExpandedView(context: FeatureContext) -> AnyView? { nil }
    func makeCompactLiveView(context: FeatureContext) -> AnyView? { nil }
    func start(context: FeatureContext) {}
    func stop() {}
}
