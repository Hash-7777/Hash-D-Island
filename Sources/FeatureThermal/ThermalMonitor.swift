import Foundation
import HashNotchKit

/// One temperature sensor reading.
public struct TempSensor: Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let celsius: Double
}

/// Reports temperatures for the notch HUD.
///
/// Primary source is the real on-die sensors via `AppleSiliconThermal`; the
/// public `ProcessInfo.thermalState` is always tracked too, both as a colour
/// signal and as a fallback label when sensor reads aren't available. Swapping
/// the sensor source later touches only this file — the feature, view, and core
/// stay put.
@MainActor
public final class ThermalMonitor: ObservableObject {
    @Published public private(set) var state: ProcessInfo.ThermalState = .nominal
    @Published public private(set) var sensors: [TempSensor] = []
    @Published public private(set) var hottestCelsius: Double?

    private let reader = AppleSiliconThermal()
    private var sampler: PollingSampler?
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

        sampler = PollingSampler(interval: 2.0) { [weak self] in self?.refresh() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func refresh() {
        let readings = reader?.read() ?? []
        sensors = readings
            .map { TempSensor(name: $0.name, celsius: $0.celsius) }
            .sorted { $0.celsius > $1.celsius }
        hottestCelsius = sensors.first?.celsius
    }

    /// True when we have real sensor values (not just the pressure label).
    public var hasReadings: Bool { hottestCelsius != nil }

    /// Compact text: the hottest die temperature, or the pressure word if no
    /// sensor reading is available.
    public var compactText: String {
        if let celsius = hottestCelsius {
            return "\(Int(celsius.rounded()))°"
        }
        return pressureLabel
    }

    /// Coarse thermal-pressure word (also drives the tint colour).
    public var pressureLabel: String {
        switch state {
        case .nominal: return "Cool"
        case .fair: return "Fair"
        case .serious: return "Warm"
        case .critical: return "Hot"
        @unknown default: return "—"
        }
    }
}
