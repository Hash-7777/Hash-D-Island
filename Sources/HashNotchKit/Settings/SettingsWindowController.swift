import AppKit
import SwiftUI

/// Owns the customization window and shows it on demand.
@MainActor
public final class SettingsWindowController {
    private let settings: SettingsStore
    private let descriptors: [FeatureDescriptor]
    private var window: NSWindow?

    public init(settings: SettingsStore, registry: FeatureRegistry) {
        self.settings = settings
        self.descriptors = registry.features.map {
            FeatureDescriptor(id: $0.id, title: $0.title, options: $0.displayOptions)
        }
    }

    public func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: settings, features: descriptors)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "HashNotch"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
