import AppKit
import SwiftUI

/// Owns the window a new install sees before any feature starts.
///
/// Centred rather than hung beside the notch, unlike settings. Settings is
/// attached to the panel because it edits it; this is not about the panel — it
/// is the one thing on screen, asked once, and it should be where the eye
/// already is rather than tucked against the top edge where a new user has not
/// yet learned to look.
@MainActor
public final class FirstRunWindowController {
    private let settings: SettingsStore
    private var window: FirstRunPanelWindow?

    /// Called when the user accepts. Whoever owns this starts the features.
    public var onAccept: () -> Void = {}
    /// Called when the user would rather pick first. Accepts as well — the
    /// reading has still been agreed to — and then opens settings so they can
    /// switch things off before they run.
    public var onChoose: () -> Void = {}

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public var isVisible: Bool { window?.isVisible == true }

    public func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.center()
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 1
        }
    }

    public func hide() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 0
        }, completionHandler: { [weak window] in
            window?.orderOut(nil)
        })
    }

    private func makeWindow() -> FirstRunPanelWindow {
        let window = FirstRunPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = FirstRunView(
            accent: settings.accent.color,
            onAccept: { [weak self] in
                self?.hide()
                self?.onAccept()
            },
            onChoose: { [weak self] in
                self?.hide()
                self?.onChoose()
            }
        )
        window.contentViewController = NSHostingController(rootView: root)
        return window
    }
}

/// Borderless, but it must take the keyboard so Return works on the button and
/// the window reads as the thing being answered rather than a picture of one.
final class FirstRunPanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
