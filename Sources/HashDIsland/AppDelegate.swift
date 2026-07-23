import AppKit
import Combine
import HashDIslandKit

/// Boots the HUD: builds the registry from the manifest, loads settings, starts
/// the features, and shows the notch overlay. There is no menu-bar item — the
/// panel's gear button is the way into settings.
/// Deliberately thin — all behavior lives in the core and the feature modules.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var registry: FeatureRegistry?
    private var context: FeatureContext?
    private var controller: NotchWindowController?
    private var settingsWindow: SettingsWindowController?
    private var power: PowerCoordinator?
    private var screenObserver: NSObjectProtocol?
    private var rebuildWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let registry = FeatureRegistry()
        registry.register(FeatureManifest.enabledFeatures())
        settings.seed(features: registry.features)

        let context = FeatureContext(settings: settings)

        // No menu-bar item: the island's gear button is the settings entry.
        let settingsWindow = SettingsWindowController(settings: settings, registry: registry)
        context.openSettings = { [weak settingsWindow] in settingsWindow?.show() }

        registry.startAll(context: context)

        let controller = NotchWindowController(registry: registry, context: context)
        controller.show()

        let power = PowerCoordinator(registry: registry, context: context)
        power.begin()

        self.registry = registry
        self.context = context
        self.controller = controller
        self.settingsWindow = settingsWindow
        self.power = power

        // Displays change under us (resolution switch, monitor plug/unplug,
        // moving to a screen with a different notch). Rebuild the overlay so it
        // is always sized and positioned for the current screen. The
        // notification fires in bursts, so coalesce.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleOverlayRebuild() }
        }

        // Battery saver changes how often everything samples, and a running
        // sampler's interval is fixed — so the features are restarted, which is
        // exactly what already happens on screen sleep and wake.
        settings.$batterySaver
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.restartFeatures() }
                }
            }
            .store(in: &cancellables)

        // A position correction changes the overlay's own geometry, which is
        // fixed when the controller is built — so the overlay is rebuilt, the
        // same way a display change already rebuilds it. Debounced, because
        // dragging a slider emits a value per tick.
        settings.$adjustments
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleOverlayRebuild() }
            }
            .store(in: &cancellables)

        // First launch: show the settings window so the app is easy to find.
        if settings.isFirstRun {
            settingsWindow.show()
        }
    }

    private func restartFeatures() {
        guard let registry, let context else { return }
        registry.stopAll()
        registry.startAll(context: context)
    }

    private func scheduleOverlayRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rebuildOverlay() }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func rebuildOverlay() {
        guard let registry, let context else { return }
        controller?.hide()
        let fresh = NotchWindowController(registry: registry, context: context)
        fresh.show()
        controller = fresh
    }

    func applicationWillTerminate(_ notification: Notification) {
        rebuildWork?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        power?.end()
        registry?.stopAll()
    }
}
