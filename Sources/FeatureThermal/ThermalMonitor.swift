import Foundation
import HashNotchKit

/// Reports the system thermal pressure using the public
/// `ProcessInfo.thermalState` API — safe and App Store friendly.
///
/// Precise per-sensor temperatures (CPU/GPU °C) need SMC/IOKit sampling; when we
/// add that, only this monitor changes — the feature, view, and core stay put.
@MainActor
public final class ThermalMonitor: ObservableObject {
    @Published public private(set) var state: ProcessInfo.ThermalState = .nominal

    private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        state = ProcessInfo.processInfo.thermalState
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state = ProcessInfo.processInfo.thermalState
            }
        }
    }

    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    /// Short label for the compact readout.
    public var label: String {
        switch state {
        case .nominal: return "Cool"
        case .fair: return "Fair"
        case .serious: return "Warm"
        case .critical: return "Hot"
        @unknown default: return "—"
        }
    }
}
