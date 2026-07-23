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
    private let notchRect: CGRect
    private var hoverMonitor: Any?
    private var localHoverMonitor: Any?
    private var scrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var lastSwipe = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var lastIslandSize: CGSize?
    private var settleWork: DispatchWorkItem?

    /// Shadow room around the island, per state — kept as tight as each
    /// state's shadow needs so a window screenshot captures the island, not a
    /// big empty box. (side, bottom).
    private static let collapsedShadow: (CGFloat, CGFloat) = (10, 12)
    private static let liveShadow: (CGFloat, CGFloat) = (14, 16)
    private static let expandedShadow: (CGFloat, CGFloat) = (26, 40)
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
        self.notchRect = geometry.notchRect

        let initial = Self.frame(for: geometry.notchRect, state: state, expanded: false, live: false, islandHeight: nil, in: screenFrame)
        self.window = NotchWindow(contentRect: initial)

        // Hover zones in screen coordinates (bottom-left origin). Opening uses a
        // TIGHT zone hugging the real notch so the panel never opens from far
        // away; the live and expanded zones cover their visible content so the
        // panel stays open while the cursor is over it.
        let notch = geometry.notchRect
        let top = screenFrame.maxY
        // Collapsed: the notch itself plus a hair of slop, reaching a little
        // below its lower edge so it is easy to catch.
        self.collapsedHoverRect = CGRect(
            x: notch.minX - 6,
            y: top - (state.collapsedHeight + 6),
            width: notch.width + 12,
            height: state.collapsedHeight + 6
        )
        // Live: the strip's actual extent (leading reach left of the notch,
        // trailing reach right of it), plus a little slop.
        let leftReach = state.liveLeadingWidth + notch.width / 2
        let rightReach = notch.width / 2 + state.liveTrailingWidth
        self.liveHoverRect = CGRect(
            x: notch.midX - leftReach - 8,
            y: top - (state.liveHeight + 6),
            width: leftReach + rightReach + 16,
            height: state.liveHeight + 6
        )
        // Expanded: the whole dropped panel.
        self.expandedHoverRect = CGRect(
            x: notch.midX - (state.expandedWidth / 2 + 6),
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
        hosting.frame = NSRect(origin: .zero, size: initial.size)
        hosting.autoresizingMask = [.width, .height]
        // Do NOT let SwiftUI resize the window to the content's ideal size — the
        // window frame is controlled solely by refitWindow(), which keeps it
        // centered on the notch. Left on, the hosting view resizes the window to
        // the island's intrinsic width (keeping the old origin) when the content
        // changes, which knocks the strip off-center for the 0.7s until the
        // settle corrects it (visible as a right-then-left shift on close).
        hosting.sizingOptions = []
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

        // Refit the window whenever the island's state changes. @Published fires
        // in willSet — BEFORE the property updates — so the refit is deferred to
        // the next main-runloop hop, by which point isExpanded / activeIDs hold
        // their new values and targetWindowFrame() reads them correctly. Reading
        // synchronously here would size the window for the OLD state (too small
        // on open → the panel is clipped to a black box or appears not to open;
        // stale width on close → the strip lands off-centre until the settle).
        state.$isExpanded
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refitWindow() } }
            }
            .store(in: &cancellables)
        context.presence.$activeIDs
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refitWindow() } }
            }
            .store(in: &cancellables)
    }

    // MARK: Window fitting (the window hugs the island)

    private func targetWindowFrame() -> NSRect {
        Self.frame(
            for: notchRect,
            state: state,
            expanded: state.isExpanded,
            live: context.presence.hasLive,
            islandHeight: lastIslandSize?.height,
            in: screenFrame
        )
    }

    /// The window is sized TIGHT to the island for the current state and stays
    /// centered on the notch (so it never nudges the island sideways). Tight
    /// means a window screenshot captures the island, not a big empty box.
    private static func frame(
        for notchRect: CGRect,
        state: NotchState,
        expanded: Bool,
        live: Bool,
        islandHeight: CGFloat?,
        in screenFrame: CGRect
    ) -> NSRect {
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        let shadow: (CGFloat, CGFloat)
        if expanded {
            contentWidth = state.expandedWidth
            contentHeight = min(islandHeight ?? provisionalExpandedHeight, screenFrame.height * 0.8)
            shadow = expandedShadow
        } else if live {
            // Symmetric about the notch so the window stays notch-centered; the
            // wider of the two reaches sets the half-width.
            let leftReach = state.liveLeadingWidth + notchRect.width / 2
            let rightReach = notchRect.width / 2 + state.liveTrailingWidth
            contentWidth = 2 * max(leftReach, rightReach)
            contentHeight = state.liveHeight
            shadow = liveShadow
        } else {
            contentWidth = state.collapsedWidth
            contentHeight = state.collapsedHeight
            shadow = collapsedShadow
        }
        let width = contentWidth + shadow.0 * 2
        let height = contentHeight + shadow.1
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
        if state.isExpanded, size.height + Self.expandedShadow.1 > window.frame.height {
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
        // Two-finger swipe on the notch: down opens the panel, up closes it.
        // Observe-only, and only ever acted on while the cursor is on the
        // island — scrolling anywhere else is ignored entirely.
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
            return event
        }
        updateHover()
    }

    private func handleScroll(_ event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) >= 10 else { return }
        guard Date().timeIntervalSince(lastSwipe) > 0.5 else { return }

        let location = NSEvent.mouseLocation
        // Natural scrolling flips the sign; normalize to finger direction.
        let fingersDown = event.isDirectionInvertedFromDevice ? delta > 0 : delta < 0

        if !state.isExpanded, fingersDown {
            let zone = context.presence.hasLive ? liveHoverRect : collapsedHoverRect
            guard zone.contains(location) else { return }
            lastSwipe = Date()
            state.setExpanded(true)
        } else if state.isExpanded, !fingersDown {
            guard expandedHoverRect.contains(location)
                || liveHoverRect.contains(location)
                || collapsedHoverRect.contains(location) else { return }
            lastSwipe = Date()
            state.setExpanded(false)
        }
    }

    private func stopHoverTracking() {
        for monitor in [hoverMonitor, localHoverMonitor, scrollMonitor, localScrollMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        hoverMonitor = nil
        localHoverMonitor = nil
        scrollMonitor = nil
        localScrollMonitor = nil
    }

    private func updateHover() {
        // Hysteresis: opening uses the tight zone for the current state (just
        // the notch, or the live strip). Staying open accepts the panel zone
        // OR any zone that can trigger opening — the keep-open area must fully
        // contain every open trigger, or hovering a spot inside one and
        // outside the other flaps open/closed on every mouse move (the live
        // strip is wider than the panel, so its far edges did exactly that).
        let location = NSEvent.mouseLocation
        let inside: Bool
        if state.isExpanded {
            inside = expandedHoverRect.contains(location)
                || liveHoverRect.contains(location)
                || collapsedHoverRect.contains(location)
        } else if context.presence.hasLive {
            inside = liveHoverRect.contains(location)
        } else {
            inside = collapsedHoverRect.contains(location)
        }
        state.setExpanded(inside)
    }
}
