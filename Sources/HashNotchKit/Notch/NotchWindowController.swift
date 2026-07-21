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
    private let liveHoverRect: CGRect
    private let expandedHoverRect: CGRect
    private var hoverMonitor: Any?

    /// Height of the top strip the overlay reserves — generous so the expanded
    /// panel is never clipped. The window is click-through, so extra height costs
    /// nothing.
    private static let stripHeight: CGFloat = 560

    public init(registry: FeatureRegistry, context: FeatureContext) {
        self.registry = registry
        self.context = context

        // No force-unwrap: launching with no screen attached (login races,
        // headless sessions) must never crash — fall back to a nominal frame
        // and let a screen-parameters change rebuild us properly.
        let screen = NotchGeometry.preferredScreen()
        let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let geometry = screen.map { NotchGeometry.current(for: $0) }
            ?? NotchGeometry(
                screenFrame: screenFrame,
                notchRect: CGRect(x: screenFrame.midX - 100, y: screenFrame.maxY - 32, width: 200, height: 32),
                hasNotch: false
            )
        self.state = NotchState(geometry: geometry)

        let frame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - Self.stripHeight,
            width: screenFrame.width,
            height: Self.stripHeight
        )
        self.window = NotchWindow(contentRect: frame)

        // Hover zones in screen coordinates (bottom-left origin), centered on the
        // notch and anchored to the top of the screen.
        let midX = screenFrame.midX
        let top = screenFrame.maxY
        self.collapsedHoverRect = CGRect(
            x: midX - (state.collapsedWidth / 2 + 14),
            y: top - (state.collapsedHeight + 6),
            width: state.collapsedWidth + 28,
            height: state.collapsedHeight + 6
        )
        self.liveHoverRect = CGRect(
            x: midX - (state.liveWidth / 2 + 8),
            y: top - (state.liveHeight + 6),
            width: state.liveWidth + 16,
            height: state.liveHeight + 6
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
            presence: context.presence,
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
        // Hysteresis: expanded keeps the whole panel open; otherwise use the tight
        // notch zone (or the slightly larger live-strip zone when something is
        // live). This stops it opening when the cursor is merely near the top.
        let zone: CGRect
        if state.isExpanded {
            zone = expandedHoverRect
        } else if context.presence.hasLive {
            zone = liveHoverRect
        } else {
            zone = collapsedHoverRect
        }
        state.setExpanded(zone.contains(NSEvent.mouseLocation))
    }
}
