import AppKit
import SwiftUI
import Combine

/// Owns the overlay window and hosts the SwiftUI HUD inside it.
///
/// The window is fully click-through, so it never interferes with the menu bar.
/// To still react to hover, a global mouse-position monitor watches for the
/// cursor entering the notch cluster and expands the HUD — observing only, never
/// swallowing the event. It also measures the frontmost app's menus (via
/// Accessibility) so the HUD can automatically move clear of them.
@MainActor
public final class NotchWindowController {
    private let window: NotchWindow
    private let state: NotchState
    private let registry: FeatureRegistry
    private let context: FeatureContext
    private let clusterScreenRect: CGRect
    private let notchLeftEdge: CGFloat
    private var hoverMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var settingsCancellable: AnyCancellable?

    /// Height of the top strip the overlay reserves — enough for the compact row
    /// plus room for the expanded panel to animate open.
    private static let stripHeight: CGFloat = 260

    /// Safety gap kept between the app's menus and the left readout.
    private static let avoidanceGap: CGFloat = 14

    public init(registry: FeatureRegistry, context: FeatureContext) {
        self.registry = registry
        self.context = context

        let screen = NotchGeometry.preferredScreen() ?? NSScreen.main!
        let geometry = NotchGeometry.current(for: screen)
        self.state = NotchState(geometry: geometry)
        self.notchLeftEdge = geometry.notchRect.minX

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - Self.stripHeight,
            width: screen.frame.width,
            height: Self.stripHeight
        )
        self.window = NotchWindow(contentRect: frame)

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
        startAvoidanceTracking()
        recomputeAvoidance()
    }

    public func hide() {
        stopHoverTracking()
        stopAvoidanceTracking()
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

    // MARK: Menu avoidance

    private func startAvoidanceTracking() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Menus can take a moment to settle after the app becomes active.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated { self?.recomputeAvoidance() }
            }
        }
        settingsCancellable = context.settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.recomputeAvoidance() }
        }
    }

    private func stopAvoidanceTracking() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        settingsCancellable = nil
    }

    private func recomputeAvoidance() {
        guard context.settings.layout.autoAvoidMenus,
              let edge = AccessibilityMenuProbe.frontmostAppMenusRightEdge() else {
            if state.leftFreeWidth != .infinity { state.leftFreeWidth = .infinity }
            return
        }
        let free = max(0, notchLeftEdge - edge - Self.avoidanceGap)
        if state.leftFreeWidth != free { state.leftFreeWidth = free }
    }
}
