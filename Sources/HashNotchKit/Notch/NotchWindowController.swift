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
    private let screenFrame: CGRect
    private var hoverMonitor: Any?
    private var localHoverMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastIslandSize: CGSize?
    private var settleWork: DispatchWorkItem?

    /// Extra window room around the island for its shadow. The window always
    /// hugs the island (plus these margins) so a window screenshot captures
    /// just the notch, never a huge invisible strip.
    private static let sideMargin: CGFloat = 30
    private static let bottomMargin: CGFloat = 46
    /// Room reserved while the panel is opening, before its first measurement.
    private static let provisionalExpandedHeight: CGFloat = 480

    public init(registry: FeatureRegistry, context: FeatureContext) {
        self.registry = registry
        self.context = context

        // No force-unwrap: launching with no screen attached (login races,
        // headless sessions) must never crash — fall back to a nominal frame
        // and let a screen-parameters change rebuild us properly.
        let screen = NotchGeometry.preferredScreen()
        let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        self.screenFrame = screenFrame
        let geometry = screen.map { NotchGeometry.current(for: $0) }
            ?? NotchGeometry(
                screenFrame: screenFrame,
                notchRect: CGRect(x: screenFrame.midX - 100, y: screenFrame.maxY - 32, width: 200, height: 32),
                hasNotch: false
            )
        self.state = NotchState(geometry: geometry)

        let initialWidth = state.collapsedWidth + Self.sideMargin * 2
        let initialHeight = state.collapsedHeight + Self.bottomMargin
        let frame = NSRect(
            x: screenFrame.midX - initialWidth / 2,
            y: screenFrame.maxY - initialHeight,
            width: initialWidth,
            height: initialHeight
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
            context: context,
            onIslandSize: { size in
                Task { @MainActor [weak self] in self?.islandSizeChanged(size) }
            }
        )

        let hosting = FirstMouseHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.acceptsMouseMovedEvents = true

        // Clicks reach the panel only while it is open; everywhere else — and
        // whenever the island is collapsed or live — the overlay stays fully
        // click-through.
        state.$isExpanded
            .removeDuplicates()
            .sink { [weak window] expanded in
                window?.ignoresMouseEvents = !expanded
            }
            .store(in: &cancellables)

        // Refit the window whenever the island's state changes.
        state.$isExpanded
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refitWindow() }
            }
            .store(in: &cancellables)
        context.presence.$activeIDs
            .removeDuplicates()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refitWindow() }
            }
            .store(in: &cancellables)
    }

    // MARK: Window fitting (the window hugs the island)

    private func targetWindowFrame() -> NSRect {
        // ONE constant width, sized for the widest state: the window's x never
        // changes, so window management can never nudge the island sideways.
        // Only the height follows the state.
        let width = max(state.expandedWidth, state.liveWidth, state.collapsedWidth)
            + Self.sideMargin * 2
        let height: CGFloat
        if state.isExpanded {
            let islandHeight = lastIslandSize?.height ?? Self.provisionalExpandedHeight
            height = min(islandHeight, screenFrame.height * 0.8) + Self.bottomMargin
        } else if context.presence.hasLive {
            height = state.liveHeight + Self.bottomMargin
        } else {
            height = state.collapsedHeight + Self.bottomMargin
        }
        return NSRect(
            x: (screenFrame.midX - width / 2).rounded(),
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Grow immediately (the animation needs room), settle to the exact fit
    /// once the spring is done. All frames share the notch's center and the
    /// screen's top edge, so growing and shrinking never moves the island.
    private func refitWindow() {
        let target = targetWindowFrame()
        let union = window.frame.union(target)
        if union != window.frame {
            window.setFrame(union, display: true)
        }
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let settled = self.targetWindowFrame()
                if self.window.frame != settled {
                    self.window.setFrame(settled, display: true)
                }
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func islandSizeChanged(_ size: CGSize) {
        lastIslandSize = size
        // If open content grew beyond the current window (e.g. a media card
        // appeared while the panel is open), make room right away.
        if state.isExpanded, size.height + Self.bottomMargin > window.frame.height {
            refitWindow()
        }
    }

    public func show() {
        refitWindow()
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
