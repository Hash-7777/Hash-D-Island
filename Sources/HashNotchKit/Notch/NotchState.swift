import SwiftUI

/// Observable UI state and sizing for the black notch island.
///
/// The island has two sizes: collapsed (matching the physical notch, so it looks
/// like the notch) and expanded (a rounded black panel that drops down below the
/// menu bar). Because the expanded content lives *below* the menu bar, it never
/// overlaps app menus or status items.
@MainActor
public final class NotchState: ObservableObject {
    /// Whether the island is expanded (dropped down) or collapsed.
    @Published public var isExpanded: Bool = false

    public let notchWidth: CGFloat
    public let notchHeight: CGFloat

    public let collapsedWidth: CGFloat
    public let collapsedHeight: CGFloat
    public let expandedWidth: CGFloat
    public let expandedHeight: CGFloat

    public init(geometry: NotchGeometry) {
        let width = geometry.notchRect.width
        let height = max(geometry.notchRect.height, 28)
        self.notchWidth = width
        self.notchHeight = height

        // Collapsed: the notch plus a small rounded lip so it reads as a tab.
        self.collapsedWidth = width
        self.collapsedHeight = height + 6

        // Expanded: a panel wide/tall enough for the readouts, dropped below.
        self.expandedWidth = max(width + 120, 420)
        self.expandedHeight = 190
    }

    public func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        // A lively spring with a touch of overshoot for a smooth, premium drop.
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            isExpanded = expanded
        }
    }
}
