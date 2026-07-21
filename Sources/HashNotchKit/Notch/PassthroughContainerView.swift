import AppKit

/// Content view for the overlay window that only captures the mouse inside a
/// defined interactive rect (the notch cluster). Everywhere else it returns nil
/// from hit testing, so clicks and hovers pass straight through to the menu bar
/// and desktop below. This is what lets the full-width overlay stay out of the
/// way while the notch area still reacts to hover.
public final class PassthroughContainerView: NSView {
    /// The region (in this view's coordinates) that should receive the mouse.
    public var interactiveFrame: CGRect = .zero

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
