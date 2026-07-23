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

    /// Whether the OS can currently manage this as a login item (true once the
    /// app is a registered bundle).
    public static var isSupported: Bool {
        SMAppService.mainApp.status != .notFound
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
            return false
        }
    }
}
