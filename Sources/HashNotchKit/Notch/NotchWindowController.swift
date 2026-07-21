import AppKit
import SwiftUI

/// Owns the overlay window and hosts the black notch island inside it.
///
/// The window is fully click-through, so it never interferes with the menu bar.
/// Hover is detected by a global mouse-position monitor that only observes the
/// cursor — it never swallows events. The hover zone is tight: while collapsed
/// it is just the notch, so the island only opens when the cursor is actually on
/// the notch; while expanded it covers the dropped panel so it stays open.
@MainActor
public final class NotchWindowController {
    private let window: NotchWindow
    private let state: NotchState
    private let registry: FeatureRegistry
    private let context: FeatureContext
    private let collapsedHoverRect: CGRect
    private let expandedHoverRect: CGRect
    private var hoverMonitor: Any?

    /// Height of the top strip the overlay reserves — enough for the expanded
    /// panel to drop down.
    private static let stripHeight: CGFloat = 300

    public init(registry: FeatureRegistry, context: FeatureContext) {
        self.registry = registry
        self.context = context

        let screen = NotchGeometry.preferredScreen() ?? NSScreen.main!
        let geometry = NotchGeometry.current(for: screen)
        self.state = NotchState(geometry: geometry)

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - Self.stripHeight,
            width: screen.frame.width,
            height: Self.stripHeight
        )
        self.window = NotchWindow(contentRect: frame)

        // Hover zones in screen coordinates (bottom-left origin), centered on the
        // notch and anchored to the top of the screen.
        let midX = screen.frame.midX
        let top = screen.frame.maxY
        self.collapsedHoverRect = CGRect(
            x: midX - (state.collapsedWidth / 2 + 14),
            y: top - (state.collapsedHeight + 6),
            width: state.collapsedWidth + 28,
            height: state.collapsedHeight + 6
        )
        self.expandedHoverRect = CGRect(
            x: midX - (state.expandedWidth / 2 + 6),
            y: top - (state.expandedHeight + 6),
            width: state.expandedWidth + 12,
            height: state.expandedHeight + 6
        )

        let root = NotchIslandView(
            state: state,
            settings: context.settings,
            registry: registry,
            context: context
        )
        .frame(width: frame.width, height: frame.height, alignment: .top)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
    }

    public func show() {
        window.orderFrontRegardless()
        startHoverTracking()
    }

    public func hide() {
        stopHoverTracking()
        window.orderOut(nil)
    }

    // MARK: Hover (observe-only, never blocks clicks)

    private func startHoverTracking() {
        guard hoverMonitor == nil else { return }
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        updateHover()
    }

    private func stopHoverTracking() {
        if let hoverMonitor {
            NSEvent.removeMonitor(hoverMonitor)
            self.hoverMonitor = nil
        }
    }

    private func updateHover() {
        // While collapsed, only the tight notch zone opens it; while expanded,
        // the whole panel keeps it open. This hysteresis stops it flickering and
        // stops it opening when the cursor is merely near the top of the screen.
        let zone = state.isExpanded ? expandedHoverRect : collapsedHoverRect
        state.setExpanded(zone.contains(NSEvent.mouseLocation))
    }
}
