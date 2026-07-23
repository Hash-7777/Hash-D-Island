import Foundation
import IOKit.ps
import HashDIslandKit

/// A transient battery moment the island announces like the iPhone does:
/// plugging in shows a brief charge pill; dropping through 20% / 10% warns.
public enum BatteryEvent: Equatable {
    case startedCharging(Int)
    case lowBattery(Int)
}

/// Reads charge level, charging state, and time remaining from IOKit power
/// sources — polled as a fallback, and refreshed instantly when the system
/// reports a power-source change (plug/unplug). Public API only.
@MainActor
public final class BatteryMonitor: ObservableObject {
    @Published public private(set) var percentage: Int = 0
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var minutesRemaining: Int?
    @Published public private(set) var hasBattery: Bool = false
    /// A short-lived announcement for the compact strip; nil when idle.
    @Published public private(set) var event: BatteryEvent?

    private var sampler: PollingSampler?
    private weak var presence: LivePresence?
    private var powerSource: CFRunLoopSource?
    private var eventWork: DispatchWorkItem?
    private var lastCharging: Bool?
    private var lastPercentage: Int?

    public init() {}

    public func start(presence: LivePresence? = nil) {
        self.presence = presence

        // Instant plug/unplug reaction; the poll below is the fallback.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.sample() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }

        sampler = PollingSampler(interval: 10.0) { [weak self] in self?.sample() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
        eventWork?.cancel()
        eventWork = nil
        event = nil
        presence?.setActive("battery", false)
    }

    /// The low-battery threshold (20 or 10) that `new` crossed downward from
    /// `old`, if any. Pure so the checks can pin the behavior.
    package static func crossedLowThreshold(from old: Int, to new: Int) -> Int? {
        for threshold in [10, 20] where old > threshold && new <= threshold {
            return threshold
        }
        return nil
    }

    private func announce(_ newEvent: BatteryEvent) {
        event = newEvent
        presence?.setActive("battery", true)
        eventWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.event = nil
                self?.presence?.setActive("battery", false)
            }
        }
        eventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
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

            // Transient announcements: plugged in, or dropped through 20%/10%.
            if let last = lastCharging, last != newCharging, newCharging {
                announce(.startedCharging(newPercentage))
            }
            if !newCharging, let lastPct = lastPercentage,
               Self.crossedLowThreshold(from: lastPct, to: newPercentage) != nil {
                announce(.lowBattery(newPercentage))
            }
            lastCharging = newCharging
            lastPercentage = newPercentage

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
