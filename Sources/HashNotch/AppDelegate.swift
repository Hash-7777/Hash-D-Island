import AppKit
import HashNotchKit

/// Boots the HUD: builds the registry from the manifest, loads settings, starts
/// the features, shows the notch overlay, and installs the menu-bar control.
/// Deliberately thin — all behavior lives in the core and the feature modules.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var registry: FeatureRegistry?
    private var controller: NotchWindowController?
    private var menuBar: MenuBarController?
    private var power: PowerCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let registry = FeatureRegistry()
        registry.register(FeatureManifest.enabledFeatures())
        settings.seed(features: registry.features)

        let context = FeatureContext(settings: settings)
        registry.startAll()

        let controller = NotchWindowController(registry: registry, context: context)
        controller.show()

        let menuBar = MenuBarController(settings: settings, registry: registry)
        let power = PowerCoordinator(registry: registry)
        power.begin()

        self.registry = registry
        self.controller = controller
        self.menuBar = menuBar
        self.power = power

        // First launch: show the settings window so the app is easy to find.
        if settings.isFirstRun {
            menuBar.showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        power?.end()
        registry?.stopAll()
    }
}
