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

        // Expanded: width sized to the content; height is generous only for the
        // hover zone (the panel itself sizes to its content).
        self.expandedWidth = max(width + 120, 300)
        self.expandedHeight = 460

        // Compact-live: content hugs the notch — a small art tile on the left,
        // a title on the right — like the iPhone's compact Dynamic Island.
        // Leading is a fixed clearance beside the notch; trailing is the MAX
        // the visible pill can reach (18pt gap + the 140pt title cap + 12pt
        // breathing room) — the pill hugs the actual content within it, and
        // this max only sizes the positioning box, the hover zone, and the
        // window so a fully-scrolling long title is always covered.
        self.liveLeadingWidth = 56
        self.liveTrailingWidth = 170
        self.liveWidth = width + self.liveLeadingWidth + self.liveTrailingWidth
        self.liveHeight = height
    }

    /// How far RIGHT the live strip must shift so its internal notch gap sits
    /// exactly on the physical notch. The sides are deliberately unequal
    /// (small art left, wide title right); centering the whole strip would
    /// land the gap (trailing − leading) / 2 points LEFT of the physical
    /// notch — which put the artwork far from the notch and buried the
    /// title's start underneath it (confirmed by photographing the physical
    /// screen; screenshots can't show this, they include the hidden pixels
    /// behind the notch).
    public var liveCenterOffset: CGFloat {
        (liveTrailingWidth - liveLeadingWidth) / 2
    }

    public func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        // The change MUST run inside an animation transaction — the island's
        // content transitions (the emerging-from-the-notch drop) only animate
        // with a transaction; without one, only the pill resizes and the
        // content pops in. Direction-aware: soft settle open, damped close.
        withAnimation(
            expanded
                ? .spring(response: 0.55, dampingFraction: 0.72)
                : .spring(response: 0.42, dampingFraction: 0.98)
        ) {
            isExpanded = expanded
        }
    }
}
