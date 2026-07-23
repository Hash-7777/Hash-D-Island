import Foundation
import HashDIslandKit

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
    private var sampler: VisibleSampler?
    private var observer: NSObjectProtocol?

    public init() {}

    public func start(visibility: PanelVisibility, scale: Double = 1) {
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

        // Sensor reads only matter while their numbers are on screen. The
        // system's own thermal-state notification above still arrives either way.
        sampler = VisibleSampler(interval: 3.0 * scale, visibility: visibility) { [weak self] in
            self?.refresh()
        }
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

        // Group cryptic sensor names (e.g. "PMU tdie7") into friendly
        // categories and keep the hottest reading per category.
        var byCategory: [String: Double] = [:]
        for reading in readings {
            let category = Self.friendlyCategory(for: reading.name)
            byCategory[category] = max(byCategory[category] ?? 0, reading.celsius)
        }

        let newSensors = byCategory
            .map { TempSensor(name: $0.key, celsius: $0.value) }
            .sorted { $0.celsius > $1.celsius }

        // Publish only on change so steady temperatures cause no redraws.
        if newSensors != sensors { sensors = newSensors }
        let newHottest = newSensors.first?.celsius
        if newHottest != hottestCelsius { hottestCelsius = newHottest }
    }

    /// Maps a raw sensor name to a friendly, human category.
    private static func friendlyCategory(for rawName: String) -> String {
        let name = rawName.lowercased()
        if name.contains("gas gauge") || name.contains("batt") { return "Battery" }
        if name.contains("gpu") { return "Graphics" }
        if name.contains("cpu") || name.contains("acc") { return "Processor" }
        if name.contains("ssd") || name.contains("nand") || name.contains("flash") { return "Storage" }
        // PMU / SOC / die / calibration sensors are the main chip — call it the processor.
        if name.contains("soc") || name.contains("pmu") || name.contains("tdie")
            || name.contains("tcal") || name.contains("tdev") || name.contains("die") {
            return "Processor"
        }
        if name.contains("air") || name.contains("ambient") || name.contains("prox") { return "System" }
        return "System"
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
