import AppKit

/// A borderless, transparent overlay window that floats above the menu bar so
/// the HUD can draw in and around the notch. It sits on every Space and does not
/// steal focus. Mouse events are enabled, but the content view
/// (`PassthroughContainerView`) only captures them over the notch cluster, so
/// the rest of the menu bar stays fully usable.
public final class NotchWindow: NSWindow {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
