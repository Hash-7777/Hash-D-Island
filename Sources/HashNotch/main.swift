import AppKit

// Run as an agent app: no Dock icon, no main window, no menu-bar item — just
// the notch overlay. `.accessory` keeps it out of the Dock and app switcher.
// The program starts on the main thread, so we assume main-actor isolation to
// wire up the app delegate and run the loop.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
