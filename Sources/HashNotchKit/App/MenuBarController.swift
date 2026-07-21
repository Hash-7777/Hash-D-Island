import AppKit

/// The menu-bar item: a small icon that opens the customization window,
/// toggles open-at-login, and quits the app. This is the app's visible control
/// surface, since HashNotch runs without a Dock icon.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settingsWindow: SettingsWindowController
    private let loginItemMenuItem = NSMenuItem(
        title: "Open at Login", action: nil, keyEquivalent: ""
    )

    public init(settings: SettingsStore, registry: FeatureRegistry) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.settingsWindow = SettingsWindowController(settings: settings, registry: registry)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "HashNotch"
        )

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(
            title: "HashNotch Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        loginItemMenuItem.action = #selector(toggleLogin)
        loginItemMenuItem.target = self
        menu.addItem(loginItemMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit HashNotch", action: #selector(quit), keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        loginItemMenuItem.state = LoginItem.isEnabled ? .on : .off
        loginItemMenuItem.isEnabled = LoginItem.isSupported
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func toggleLogin() {
        _ = LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
