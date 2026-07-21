import AppKit
import HashNotchKit

/// Boots the HUD: builds the registry from the manifest, starts the features,
/// and shows the notch overlay. Deliberately thin — all behavior lives in the
/// core and the feature modules.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var registry: FeatureRegistry?
    private var controller: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = FeatureContext()
        let registry = FeatureRegistry()
        registry.register(FeatureManifest.enabledFeatures())
        registry.startAll()

        let controller = NotchWindowController(registry: registry, context: context)
        controller.show()

        self.registry = registry
        self.controller = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry?.stopAll()
    }
}
