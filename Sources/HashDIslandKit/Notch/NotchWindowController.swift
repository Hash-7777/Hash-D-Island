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
    // All four vary with the measured geometry, which a size or position
    // slider changes live.
    private var collapsedHoverRect: CGRect = .zero
    private var expandedHoverRect: CGRect = .zero
    private var screenFrame: CGRect
    private var notchRect: CGRect
    /// The y coordinate the island hangs from — the screen's top edge on a
    /// notched display, the bottom of the menu bar otherwise.
    private var islandTop: CGFloat
    private var hoverMonitor: Any?
    private var localHoverMonitor: Any?
    private var scrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var lastSwipe = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var lastIslandSize: CGSize?
    private var settleWork: DispatchWorkItem?
    private var isPinnedOpen = false

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
        let measured = screen.map { NotchGeometry.current(for: $0) }
            ?? NotchGeometry(
                screenFrame: screenFrame,
                notchRect: CGRect(
                    x: screenFrame.midX - NotchGeometry.notchlessWidth / 2,
                    y: screenFrame.maxY - NotchGeometry.notchlessHeight,
                    width: NotchGeometry.notchlessWidth,
                    height: NotchGeometry.notchlessHeight
                ),
                hasNotch: false
            )
        // Whatever was measured, the user's own correction for this display has
        // the last word.
        let adjustment = screen.map { context.settings.adjustment(for: NotchGeometry.displayKey(for: $0)) }
            ?? IslandAdjustment()
        let geometry = adjustment.applied(to: measured)

        self.state = NotchState(geometry: geometry)
        self.notchRect = geometry.notchRect
        self.islandTop = geometry.islandTop

        let initial = Self.frame(
            for: geometry.notchRect,
            state: state,
            expanded: false,
            live: false,
            islandHeight: nil,
            topEdge: geometry.islandTop,
            in: screenFrame
        )
        self.window = NotchWindow(contentRect: initial)

        updateHoverRects()

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

        // A position correction reshapes the island in place, on every tick of
        // the slider. Deliberately undebounced: this is what makes the sliders
        // move the island under your hand rather than after you let go. The
        // controller watches for it itself because the geometry is its own.
        context.settings.$adjustments
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] adjustments in
                // The NEW value is taken from the publisher, never re-read from
                // the store: @Published fires in willSet, where the property
                // still holds the old value, so re-reading it here would move
                // the island to where it already was.
                MainActor.assumeIsolated { self?.refreshGeometry(using: adjustments) }
            }
            .store(in: &cancellables)

        // Tell the panel-only features whether anyone is looking, so they can
        // stop sampling entirely while the panel is shut. This reads the value
        // the sink is handed, not the property — @Published fires in willSet,
        // where the property still holds the old one.
        state.$isExpanded
            .removeDuplicates()
            .sink { [weak context] expanded in
                MainActor.assumeIsolated { context?.visibility.setOpen(expanded) }
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

    // MARK: Live geometry

    /// How tall the open panel is, given what it measured.
    ///
    /// ONE function, used by the window frame AND by the keep-open zone. They
    /// used to work it out separately and drifted apart twice: once the zone
    /// was left at a nominal height the window had long stopped using, which
    /// put the last row outside it; and the window capped the panel at four
    /// fifths of the screen while the zone did not, so a tall enough panel
    /// would have been clipped by one and overshot by the other. Two
    /// calculations of the same quantity is the bug, not either answer.
    ///
    /// The ceiling is the room actually below the island rather than a
    /// proportion of the whole screen — the menu bar is not available and the
    /// screen's height says nothing about what is. A margin is left at the
    /// bottom so the panel never runs into the very edge of the display.
    package static let panelBottomMargin: CGFloat = 24

    package static func expandedContentHeight(
        measured: CGFloat?,
        islandTop: CGFloat,
        screenFrame: CGRect
    ) -> CGFloat {
        let available = max(0, islandTop - screenFrame.minY - panelBottomMargin)
        let wanted = measured ?? provisionalExpandedHeight
        return min(wanted, available)
    }

    /// The region that keeps the panel open, for a panel of a given height.
    ///
    /// The height must be the MEASURED one, not the nominal 460 the state
    /// carries. The panel grows with whatever is turned on, and the window
    /// already sizes itself from the measurement — but this zone did not, so
    /// with everything enabled it covered the top two thirds of a panel that
    /// reached most of the way down the screen. Moving the cursor toward the
    /// last row left the zone before reaching it, and the panel shut in the
    /// user's face. The timer sits last, so the timer was unreachable.
    ///
    /// Generous at the bottom on purpose: that edge is the one people approach
    /// slowly, having already travelled the length of the panel to get there.
    ///
    /// Pure and package-visible, because the failure only appears at heights a
    /// checkout does not reproduce on every machine.
    package static func expandedZone(
        notchRect: CGRect,
        islandTop: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let slop: CGFloat = 12
        return CGRect(
            x: notchRect.midX - (width / 2 + 6),
            y: islandTop - (height + slop),
            width: width + 12,
            height: height + slop
        )
    }

    /// The overlay's current frame. Package-visible so the checks can prove a
    /// correction actually moves the window.
    package var currentWindowFrame: NSRect { window.frame }

    /// The only region that opens the panel, and the region that keeps it open.
    /// Package-visible so the checks can prove the first never grows to cover
    /// the menu bar's own status items, and that it stays inside the second.
    package var openZone: CGRect { collapsedHoverRect }
    /// The measured notch this overlay is built around.
    package var currentNotchRect: CGRect { notchRect }

    /// Where the open panel sits on screen, for anything that hangs off it.
    public var panelAnchor: CGRect {
        let height = Self.expandedContentHeight(
            measured: lastIslandSize?.height, islandTop: islandTop, screenFrame: screenFrame
        )
        return CGRect(
            x: notchRect.midX - state.expandedWidth / 2,
            y: islandTop - height,
            width: state.expandedWidth,
            height: height
        )
    }

    /// Holds the panel open regardless of where the cursor is.
    ///
    /// Set while settings is showing beside it. Without this the panel closes
    /// the instant the cursor leaves it to reach the settings — which is the
    /// only way to get there — and the settings would be left hanging next to
    /// nothing, which is the opposite of being attached to it.
    public func setPinnedOpen(_ pinned: Bool) {
        guard isPinnedOpen != pinned else { return }
        isPinnedOpen = pinned
        if pinned {
            state.setExpanded(true)
        } else {
            updateHover()
        }
    }
    package var keepOpenZone: CGRect { expandedHoverRect.union(collapsedHoverRect) }

    /// Re-measure the current screen, apply the user's correction for it, and
    /// reshape everything in place.
    ///
    /// This is what lets the Position sliders move the island under your hand.
    /// Rebuilding the whole overlay on every tick of a drag would be far too
    /// heavy — and, being debounced, it only landed once you let go, which is
    /// exactly the lag this replaces.
    public func refreshGeometry() {
        refreshGeometry(using: context.settings.adjustments)
    }

    /// As above, but told which corrections to use rather than reading them.
    private func refreshGeometry(using adjustments: [String: IslandAdjustment]) {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let measured = NotchGeometry.current(for: screen)
        let adjustment = adjustments[NotchGeometry.displayKey(for: screen)] ?? IslandAdjustment()
        apply(geometry: adjustment.applied(to: measured))
    }

    private func apply(geometry: NotchGeometry) {
        screenFrame = geometry.screenFrame
        notchRect = geometry.notchRect
        islandTop = geometry.islandTop
        state.apply(geometry: geometry)
        updateHoverRects()
        // Straight to the exact frame: an animated resize per slider tick would
        // trail the drag rather than follow it.
        let target = targetWindowFrame()
        if window.frame != target { window.setFrame(target, display: true) }
        updateHover()
    }

    /// Hover zones in screen coordinates (bottom-left origin).
    ///
    /// Two of them, and the relationship between them is the whole rule:
    /// **the notch opens the panel, and the panel keeps itself open.** The
    /// keep-open area must fully contain the opening one, or a point inside one
    /// and outside the other flaps open and closed on every mouse move.
    ///
    /// Both hang from the island's own top edge, which is the screen's edge
    /// only when there is a notch to sit in.
    private func updateHoverRects() {
        let notch = notchRect
        let top = islandTop

        // The ONLY zone that opens the panel: the notch itself, plus a hair of
        // slop reaching a little below its lower edge so it is easy to catch.
        //
        // Never the live strip. The strip is wide — its trailing side alone
        // reaches 170 points past the notch's centre — and the menu bar's own
        // status items sit in exactly that space. Treating the strip as a
        // trigger meant reaching for the camera icon, or the Wi-Fi menu, opened
        // the panel over the very thing being reached for. The strip is
        // something to read, not something to press; opening is the notch's
        // job, whether or not anything is live.
        collapsedHoverRect = CGRect(
            x: notch.minX - 6,
            y: top - (state.collapsedHeight + 6),
            width: notch.width + 12,
            height: state.collapsedHeight + 6
        )
        // Expanded: the whole dropped panel, at the height it actually is.
        expandedHoverRect = Self.expandedZone(
            notchRect: notch,
            islandTop: top,
            width: state.expandedWidth,
            height: Self.expandedContentHeight(
                measured: lastIslandSize?.height,
                islandTop: top,
                screenFrame: screenFrame
            )
        )
    }

    // MARK: Window fitting (the window hugs the island)

    private func targetWindowFrame() -> NSRect {
        Self.frame(
            for: notchRect,
            state: state,
            expanded: state.isExpanded,
            live: context.presence.hasLive,
            islandHeight: lastIslandSize?.height,
            topEdge: islandTop,
            in: screenFrame
        )
    }

    /// The widest the window ever needs to be, whatever state the island is in.
    ///
    /// This is deliberately NOT sized to the current state. A window whose width
    /// changes has to move its left edge to stay centred on the notch, and that
    /// move is instant while SwiftUI animates the content re-centring inside it
    /// — the two do not cancel, and the island visibly sweeps sideways. Measured
    /// on a real close: the panel sat at 262 in a 524-wide window, then at 176
    /// in a 352-wide one. Both are the same point on screen; getting between
    /// them is what you see.
    ///
    /// One constant width costs nothing. The window is transparent and
    /// click-through, so the extra space is invisible.
    package static func constantWidth(for notchRect: CGRect, state: NotchState) -> CGFloat {
        let collapsed = state.collapsedWidth + collapsedShadow.0 * 2
        // Symmetric about the notch, so the wider of the two reaches sets it.
        let leftReach = state.liveLeadingWidth + notchRect.width / 2
        let rightReach = notchRect.width / 2 + state.liveTrailingWidth
        let live = 2 * max(leftReach, rightReach) + liveShadow.0 * 2
        let expanded = state.expandedWidth + expandedShadow.0 * 2
        return max(collapsed, max(live, expanded)).rounded()
    }

    /// The window keeps one width and one x for the whole of its life, centred
    /// on the notch. Only its HEIGHT follows the state, because growing
    /// downwards moves nothing that is anchored to the top.
    private static func frame(
        for notchRect: CGRect,
        state: NotchState,
        expanded: Bool,
        live: Bool,
        islandHeight: CGFloat?,
        topEdge: CGFloat,
        in screenFrame: CGRect
    ) -> NSRect {
        let contentHeight: CGFloat
        let shadowBottom: CGFloat
        if expanded {
            contentHeight = expandedContentHeight(
                measured: islandHeight, islandTop: topEdge, screenFrame: screenFrame
            )
            shadowBottom = expandedShadow.1
        } else if live {
            contentHeight = state.liveHeight
            shadowBottom = liveShadow.1
        } else {
            contentHeight = state.collapsedHeight
            shadowBottom = collapsedShadow.1
        }

        let width = constantWidth(for: notchRect, state: state)
        let height = contentHeight + shadowBottom
        // Centred on the island's own notch rather than the screen, so a
        // sideways correction actually moves it, and hung from the island's top
        // edge rather than the screen's.
        return NSRect(
            x: (notchRect.midX - width / 2).rounded(),
            y: topEdge - height,
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
            debugLog("grow")
        }
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let settled = self.targetWindowFrame()
                if self.window.frame != settled {
                    self.window.setFrame(settled, display: true)
                    self.debugLog("settle")
                }
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func islandSizeChanged(_ size: CGSize) {
        lastIslandSize = size
        // The keep-open zone is derived from this, so it has to be rebuilt the
        // moment the panel's real height is known — and again whenever it
        // changes, because turning an indicator on makes the panel taller.
        updateHoverRects()

        // Then follow the content, in BOTH directions.
        //
        // This used to refit only when the panel had outgrown its window, which
        // left the window too tall after content went away and meant the fit
        // was only ever corrected by the settle pass afterwards. Comparing
        // against the height actually wanted covers growing and shrinking with
        // one rule, and skips the no-ops — a measurement that changes nothing
        // schedules nothing.
        guard state.isExpanded else { return }
        let wanted = Self.expandedContentHeight(
            measured: size.height, islandTop: islandTop, screenFrame: screenFrame
        ) + Self.expandedShadow.1
        if abs(window.frame.height - wanted) > 1 { refitWindow() }
    }

    /// Development aid, off unless `HASHDISLAND_DEBUG` is set.
    ///
    /// `frames` reports every window frame the controller sets, with the island
    /// size that prompted it, which is the only way to tell a drifting window
    /// apart from drifting content inside a still one. `cycle` opens and closes
    /// the panel on a timer so that motion can be measured without a hand on
    /// the trackpad.
    private static var debugOptions: Set<String> {
        Set((ProcessInfo.processInfo.environment["HASHDISLAND_DEBUG"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private func debugLog(_ label: String) {
        guard Self.debugOptions.contains("frames") else { return }
        let f = window.frame
        FileHandle.standardError.write(Data("""
        [island] \(label) window x=\(Int(f.minX)) w=\(Int(f.width)) h=\(Int(f.height)) \
        midX=\(Int(f.midX)) top=\(Int(f.maxY)) | island=\(Int(lastIslandSize?.width ?? -1))x\(Int(lastIslandSize?.height ?? -1)) \
        | expanded=\(state.isExpanded) live=\(context.presence.hasLive)

        """.utf8))
    }

    private func startDebugCycleIfRequested() {
        guard Self.debugOptions.contains("cycle") else { return }
        var open = false
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                open.toggle()
                self?.state.setExpanded(open)
            }
        }
    }

    public func show() {
        refitWindow()
        window.orderFrontRegardless()
        startHoverTracking()
        startDebugCycleIfRequested()
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
        guard !isPinnedOpen else { return }
        let delta = event.scrollingDeltaY
        guard abs(delta) >= 10 else { return }
        guard Date().timeIntervalSince(lastSwipe) > 0.5 else { return }

        let location = NSEvent.mouseLocation
        // Natural scrolling flips the sign; normalize to finger direction.
        let fingersDown = event.isDirectionInvertedFromDevice ? delta > 0 : delta < 0

        if !state.isExpanded, fingersDown {
            guard collapsedHoverRect.contains(location) else { return }
            lastSwipe = Date()
            state.setExpanded(true)
        } else if state.isExpanded, !fingersDown {
            guard expandedHoverRect.contains(location)
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
        // Pinned beats everything: while settings is open beside the panel,
        // the cursor is expected to be away from the island.
        guard !isPinnedOpen else {
            state.setExpanded(true)
            return
        }
        let location = NSEvent.mouseLocation
        let inside: Bool
        if state.isExpanded {
            inside = expandedHoverRect.contains(location)
                || collapsedHoverRect.contains(location)
        } else {
            inside = collapsedHoverRect.contains(location)
        }
        state.setExpanded(inside)
    }
}
