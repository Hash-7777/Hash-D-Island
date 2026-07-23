import AppKit

/// Measures where the island should sit on a given screen, using public AppKit
/// APIs only.
///
/// On a notched Mac, `safeAreaInsets.top` is the notch height and the
/// `auxiliaryTop*Area` rects are the usable menu-bar strips either side of it —
/// the gap between them is the notch itself, and the island wears it exactly.
///
/// On a screen **without** a notch there is nothing to blend into, and the top
/// of the screen is the menu bar. Painting a black shape up there would cover
/// it, which reads as a fault rather than a feature. So the island hangs below
/// the menu bar instead, as a small pill of its own: deliberate, not broken.
public struct NotchGeometry {
    public let screenFrame: CGRect
    public let notchRect: CGRect
    public let hasNotch: Bool
    /// The y coordinate the island hangs from: the screen's top edge when there
    /// is a notch to match, the bottom of the menu bar when there is not.
    public let islandTop: CGFloat

    public init(
        screenFrame: CGRect,
        notchRect: CGRect,
        hasNotch: Bool,
        islandTop: CGFloat? = nil
    ) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.hasNotch = hasNotch
        self.islandTop = islandTop ?? screenFrame.maxY
    }

    /// The stand-in island's size on a screen with no notch. Narrow enough to
    /// read as a deliberate pill rather than a bar across the top.
    public static let notchlessWidth: CGFloat = 132
    public static let notchlessHeight: CGFloat = 26

    public static func current(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchRect = CGRect(
                x: left.maxX,
                y: frame.maxY - topInset,
                width: max(0, right.minX - left.maxX),
                height: topInset
            )
            return NotchGeometry(
                screenFrame: frame,
                notchRect: notchRect,
                hasNotch: true,
                islandTop: frame.maxY
            )
        }

        // No notch: hang the island from the bottom of the menu bar, centered.
        let top = frame.maxY - menuBarHeight(for: screen)
        let notchRect = CGRect(
            x: frame.midX - notchlessWidth / 2,
            y: top - notchlessHeight,
            width: notchlessWidth,
            height: notchlessHeight
        )
        return NotchGeometry(
            screenFrame: frame,
            notchRect: notchRect,
            hasNotch: false,
            islandTop: top
        )
    }

    /// How tall the menu bar is on this screen. The status bar's own thickness
    /// is the reliable answer; the others are floors for the case where the
    /// system reports something implausible.
    package static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        let reported = NSStatusBar.system.thickness
        let unusable = screen.frame.maxY - screen.visibleFrame.maxY
        return max(reported, min(unusable, 40), 24)
    }

    /// The screen most likely to have a notch, else the main screen.
    public static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    /// A stable key for remembering per-display adjustments. Falls back to the
    /// frame size when the display id is unavailable, which still tells two
    /// differently sized screens apart.
    public static func displayKey(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        let frame = screen.frame
        return "frame-\(Int(frame.width))x\(Int(frame.height))"
    }
}
