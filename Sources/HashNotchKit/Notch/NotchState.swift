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
    public let liveLeadingWidth: CGFloat
    public let liveTrailingWidth: CGFloat
    public let liveWidth: CGFloat
    public let liveHeight: CGFloat
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

        // Expanded: sized to the content (a column of rows) plus padding, so the
        // panel hugs its content instead of leaving a big empty margin.
        self.expandedWidth = max(width + 120, 300)
        self.expandedHeight = 380

        // Compact-live: content hugs the notch — a small art tile on the left,
        // a title on the right — like the iPhone's compact Dynamic Island.
        self.liveLeadingWidth = 46
        self.liveTrailingWidth = 172
        self.liveWidth = width + self.liveLeadingWidth + self.liveTrailingWidth
        self.liveHeight = height
    }

    public func setExpanded(_ expanded: Bool) {
        // The island view animates the size change via `.animation(value:)`.
        guard expanded != isExpanded else { return }
        isExpanded = expanded
    }
}
