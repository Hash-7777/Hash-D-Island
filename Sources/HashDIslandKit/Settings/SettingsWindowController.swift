import AppKit
import SwiftUI

/// The window settings live in: borderless, rounded, and hung beside the panel
/// rather than floating in the middle of the screen.
///
/// A titled window centred on the display was a different object from the thing
/// that opened it — you clicked a gear on the notch and a piece of ordinary Mac
/// furniture appeared somewhere else. Anchoring it to the panel keeps the two
/// as one surface, which is the whole idea the island is built on.
///
/// It can become key so the controls inside respond to the keyboard, which a
/// borderless window does not do by default.
final class SettingsPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the customization panel, and slides it out beside the island.
@MainActor
public final class SettingsWindowController {
    private let settings: SettingsStore
    private let descriptors: [FeatureDescriptor]
    private var window: SettingsPanelWindow?
    private var escapeMonitor: Any?

    /// Told whenever the panel appears or disappears, so whatever it is
    /// attached to can stay open for as long as it is showing. Without this the
    /// island would collapse the moment the cursor left it to come here, and
    /// the settings would be left hanging beside nothing.
    public var onVisibilityChange: (Bool) -> Void = { _ in }

    /// Wide enough for a sidebar and a column of controls, narrow enough to sit
    /// beside the panel on a laptop display — there are only about 490 points
    /// to the right of the island on this size of screen, and a window that
    /// does not fit beside the thing it belongs to is not attached to anything.
    private static let size = CGSize(width: 460, height: 580)
    /// The gap between the island's edge and this one.
    private static let gap: CGFloat = 12
    /// How far it starts to the left of its resting place, so it reads as
    /// coming out from behind the island rather than fading in on the spot.
    private static let slideFrom: CGFloat = 26

    public init(settings: SettingsStore, registry: FeatureRegistry) {
        self.settings = settings
        self.descriptors = registry.features.map {
            FeatureDescriptor(id: $0.id, title: $0.title, options: $0.displayOptions)
        }
    }

    public var isVisible: Bool { window?.isVisible == true }

    /// The gear is one button, so it is one button both ways.
    public func toggle(anchor: CGRect, on screen: NSScreen?) {
        isVisible ? hide() : show(anchor: anchor, on: screen)
    }

    public func show(anchor: CGRect, on screen: NSScreen?) {
        let window = window ?? makeWindow()
        self.window = window

        let visible = screen?.visibleFrame ?? NSScreen.main?.frame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let target = Self.frame(besideAnchor: anchor, in: visible)
        // Start tucked behind the island and transparent, then travel out.
        var start = target
        start.origin.x -= Self.slideFrom
        window.setFrame(start, display: false)
        window.alphaValue = 0

        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        onVisibilityChange(true)
        beginWatchingForEscape()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            // Decelerating rather than eased both ends: it should leave the
            // island quickly and arrive gently, the way a drawer does.
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 1
        }
    }

    public func hide() {
        guard let window, window.isVisible else { return }
        stopWatchingForEscape()

        var away = window.frame
        away.origin.x -= Self.slideFrom
        NSAnimationContext.runAnimationGroup { context in
            // Quicker going than coming. Leaving should not be something you
            // wait for.
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(away, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.onVisibilityChange(false)
        }
    }

    // MARK: Placement

    /// Where it sits: hung from the same top edge as the panel, just past its
    /// right side, and pulled back onto the display if there is not room —
    /// better to overlap the island slightly than to run off the screen.
    package static func frame(besideAnchor anchor: CGRect, in visible: CGRect) -> NSRect {
        let height = min(size.height, max(200, anchor.maxY - visible.minY - 24))
        var x = anchor.maxX + gap
        if x + size.width > visible.maxX - 12 {
            x = max(visible.minX + 12, visible.maxX - 12 - size.width)
        }
        return NSRect(x: x.rounded(), y: (anchor.maxY - height).rounded(), width: size.width, height: height)
    }

    // MARK: Plumbing

    private func makeWindow() -> SettingsPanelWindow {
        let window = SettingsPanelWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        // Above the menu bar, like the island it belongs to, and present on
        // whichever Space the user is on.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let root = SettingsView(settings: settings, features: descriptors) { [weak self] in
            self?.hide()
        }
        window.contentViewController = NSHostingController(rootView: root)
        return window
    }

    /// Escape closes it, which is the one keystroke everybody tries on a panel
    /// that has no title bar to close.
    private func beginWatchingForEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.hide() }
            return nil
        }
    }

    private func stopWatchingForEscape() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }
}
