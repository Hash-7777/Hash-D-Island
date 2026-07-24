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
        // The gear opens settings beside the panel it was clicked from, and
        // holds that panel open for as long as they are both showing.
        context.openSettings = { [weak self] in self?.toggleSettings() }
        settingsWindow.onVisibilityChange = { [weak self] visible in
            self?.controller?.setPinnedOpen(visible)
        }

        // Only the features that are switched on are started at all.
        registry.syncRunning(context: context)

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

        // How often the token count runs is fixed when its sampler starts, for
        // the same reason battery saver is: an interval cannot be changed under
        // a running timer. Restarting is what already happens on screen sleep
        // and wake, so it is a path the features are built to survive.
        settings.$tokenScanInterval
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.restartFeatures() }
                }
            }
            .store(in: &cancellables)

        // Switching a feature off stops it reading, not just showing. The
        // whole config dictionary is watched because @Published fires for any
        // change in it (a reorder, a style); syncRunning only touches a feature
        // whose on/off state actually differs from what it is doing, so the
        // extra calls cost nothing. Deferred a hop because @Published fires in
        // willSet, where the store still holds the previous value.
        settings.$features
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.syncFeatures() }
                }
            }
            .store(in: &cancellables)

        // Position corrections are watched by the overlay controller itself,
        // which owns the geometry they change.

        // Development aid, inert unless HASHDISLAND_DEBUG asks for it. Whether
        // the system will accept this bundle as a login item cannot be learned
        // from outside the app — SMAppService always answers about whoever is
        // asking — so the only way to see the real error is from in here.
        if (ProcessInfo.processInfo.environment["HASHDISLAND_DEBUG"] ?? "").contains("login") {
            FileHandle.standardError.write(Data(
                "[login] bundle=\(Bundle.main.bundleURL.path)\n[login] status=\(LoginItem.statusDescription)\n".utf8
            ))
            let ok = LoginItem.setEnabled(true)
            FileHandle.standardError.write(Data(
                "[login] register returned \(ok), status now \(LoginItem.statusDescription)\n".utf8
            ))
        }

        // First launch: show the settings window so the app is easy to find.
        if settings.isFirstRun {
            settingsWindow.show(anchor: controller.panelAnchor, on: NotchGeometry.preferredScreen())
        }
    }

    private func restartFeatures() {
        guard let registry, let context else { return }
        registry.stopAll()
        registry.syncRunning(context: context)
    }

    private func toggleSettings() {
        guard let controller, let settingsWindow else { return }
        settingsWindow.toggle(anchor: controller.panelAnchor, on: NotchGeometry.preferredScreen())
    }

    /// Start or stop the features whose switch has just changed.
    private func syncFeatures() {
        guard let registry, let context else { return }
        registry.syncRunning(context: context)
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
        // A display change builds a new overlay, and the new one knows nothing
        // about the settings still open beside it. Without this the panel it is
        // attached to would quietly collapse behind it.
        if settingsWindow?.isVisible == true { fresh.setPinnedOpen(true) }
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
