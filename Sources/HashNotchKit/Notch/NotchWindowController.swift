import AppKit
import SwiftUI
import Combine

/// Lets SwiftUI buttons in the panel react to the very first click, without
/// the window having to become key first.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the overlay window and hosts the black notch island inside it.
///
/// While collapsed or live the window is fully click-through, so it can never
/// interfere with the menu bar or anything else. Only while the panel is open
/// does it accept clicks (for the media controls); the instant the cursor
/// leaves the panel it collapses and turns click-through again. Hover is
/// detected by mouse-position monitors that only observe the cursor — they
/// never swallow events. The hover zone is tight: while collapsed it is just
/// the notch, so the island only opens when the cursor is actually on the
/// notch; while expanded it covers the dropped panel so it stays open.
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
    private var localHoverMonitor: Any?
    private var expandCancellable: AnyCancellable?

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

        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.acceptsMouseMovedEvents = true

        // Clicks reach the panel only while it is open; everywhere else — and
        // whenever the island is collapsed or live — the overlay stays fully
        // click-through.
        expandCancellable = state.$isExpanded
            .removeDuplicates()
            .sink { [weak window] expanded in
                window?.ignoresMouseEvents = !expanded
            }
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
        // Global monitors never see our own app's events — while the panel is
        // open and interactive, moves over it arrive here instead.
        localHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateHover() }
            return event
        }
        updateHover()
    }

    private func stopHoverTracking() {
        if let hoverMonitor {
            NSEvent.removeMonitor(hoverMonitor)
            self.hoverMonitor = nil
        }
        if let localHoverMonitor {
            NSEvent.removeMonitor(localHoverMonitor)
            self.localHoverMonitor = nil
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
