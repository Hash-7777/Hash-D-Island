import AppKit
import SwiftUI

/// Owns the overlay window and hosts the SwiftUI HUD inside it.
///
/// The window is fully click-through, so it never interferes with the menu bar.
/// To still react to hover, a global mouse-position monitor watches for the
/// cursor entering the notch cluster and expands the HUD — observing only, never
/// swallowing the event.
@MainActor
public final class NotchWindowController {
    private let window: NotchWindow
    private let state: NotchState
    private let registry: FeatureRegistry
    private let context: FeatureContext
    private let clusterScreenRect: CGRect
    private var hoverMonitor: Any?

    /// Height of the top strip the overlay reserves — enough for the compact row
    /// plus room for the expanded panel to animate open.
    private static let stripHeight: CGFloat = 260

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

        // The screen-space region (bottom-left origin) that counts as "hovering
        // the notch". Centered on the notch, wide enough to cover the readouts
        // and tall enough to reach into the expanded panel.
        let halfWidth = geometry.notchRect.width / 2 + 240
        self.clusterScreenRect = CGRect(
            x: screen.frame.midX - halfWidth,
            y: screen.frame.maxY - 170,
            width: halfWidth * 2,
            height: 170
        )

        let root = NotchContainerView(
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
    }

    private func stopHoverTracking() {
        if let hoverMonitor {
            NSEvent.removeMonitor(hoverMonitor)
            self.hoverMonitor = nil
        }
    }

    private func updateHover() {
        let inside = clusterScreenRect.contains(NSEvent.mouseLocation)
        guard inside != state.isExpanded else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            state.isExpanded = inside
        }
    }
}
