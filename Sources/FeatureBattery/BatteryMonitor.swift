import Foundation
import IOKit.ps
import HashNotchKit

/// Reads charge level, charging state, and time remaining from IOKit power
/// sources. Public API only.
@MainActor
public final class BatteryMonitor: ObservableObject {
    @Published public private(set) var percentage: Int = 0
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var minutesRemaining: Int?
    @Published public private(set) var hasBattery: Bool = false

    private var sampler: PollingSampler?

    public init() {}

    public func start() {
        sampler = PollingSampler(interval: 10.0) { [weak self] in self?.sample() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
    }

    private func sample() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            hasBattery = false
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            let current = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let newPercentage = maximum > 0 ? Int((Double(current) / Double(maximum)) * 100.0) : current

            let state = description[kIOPSPowerSourceStateKey as String] as? String
            let newCharging = (description[kIOPSIsChargingKey as String] as? Bool)
                ?? (state == kIOPSACPowerValue)

            let timeToEmpty = description[kIOPSTimeToEmptyKey as String] as? Int
            let newRemaining = (timeToEmpty ?? -1) > 0 ? timeToEmpty : nil

            // Assign only on real change so identical samples cause no redraws.
            if percentage != newPercentage { percentage = newPercentage }
            if isCharging != newCharging { isCharging = newCharging }
            if minutesRemaining != newRemaining { minutesRemaining = newRemaining }
            if !hasBattery { hasBattery = true }
            return
        }

        if hasBattery { hasBattery = false }
    }
}
