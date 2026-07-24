import AppKit
import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService` for "open at login".
///
/// This only takes effect when Hash D Island runs as a proper `.app` bundle (see
/// scripts/build_app.sh); from a bare `swift run` binary the register call is a
/// no-op that throws, which callers treat as "not available yet".
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether this copy is even able to be a login item.
    ///
    /// Asked of the BUNDLE, not of the registration. It used to be
    /// `status != .notFound`, and `.notFound` is precisely what an app that has
    /// never been registered reports — which is the state everybody is in
    /// before they switch it on. So the switch was disabled for exactly the
    /// people trying to use it, explaining that the feature would be available
    /// once the app was installed as an app, while running as an installed app.
    /// Nothing else registers it, so it could never become available.
    ///
    /// macOS manages login items by bundle, so being a bundle is the whole
    /// requirement: a bare `swift run` binary has no identifier and cannot,
    /// an installed `.app` can.
    public static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
            && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// The user has been asked and has not said yes yet. macOS parks the
    /// request in System Settings rather than prompting, so an app that does
    /// not mention this leaves the switch looking simply broken.
    public static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Opens the pane where a parked request is approved.
    public static func openLoginItemsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            // Say why. This used to fail in silence, so the switch simply
            // sprang back and there was nothing anywhere to explain it —
            // which is the least helpful way for a permission-shaped failure
            // to behave.
            FileHandle.standardError.write(Data(
                "Hash D Island: could not \(enabled ? "register" : "unregister") the login item — \(error)\n".utf8
            ))
            return false
        }
    }

    /// What the system currently thinks, in words.
    package static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }
}
