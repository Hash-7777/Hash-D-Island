import AppKit

/// Measures the physical notch on the current screen using public AppKit APIs.
///
/// On a notched Mac, `safeAreaInsets.top` is the notch height and the
/// `auxiliaryTop*Area` rects are the usable menu-bar strips either side of it —
/// the gap between them is the notch itself. On a Mac without a notch (or an
/// external display) we fall back to a sensible centered strip so the HUD still
/// has somewhere to live during development.
public struct NotchGeometry {
    public let screenFrame: CGRect
    public let notchRect: CGRect
    public let hasNotch: Bool

    public init(screenFrame: CGRect, notchRect: CGRect, hasNotch: Bool) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.hasNotch = hasNotch
    }

    public static func current(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top
        let hasNotch = topInset > 0

        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let minX = left.maxX
            let maxX = right.minX
            let notchRect = CGRect(
                x: minX,
                y: frame.maxY - topInset,
                width: max(0, maxX - minX),
                height: topInset
            )
            return NotchGeometry(screenFrame: frame, notchRect: notchRect, hasNotch: true)
        }

        // Fallback: a virtual notch centered at the top of the screen.
        let fallbackWidth: CGFloat = 200
        let fallbackHeight: CGFloat = 32
        let notchRect = CGRect(
            x: frame.midX - fallbackWidth / 2,
            y: frame.maxY - fallbackHeight,
            width: fallbackWidth,
            height: fallbackHeight
        )
        return NotchGeometry(screenFrame: frame, notchRect: notchRect, hasNotch: false)
    }

    /// The screen most likely to have a notch, else the main screen.
    public static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }
}
