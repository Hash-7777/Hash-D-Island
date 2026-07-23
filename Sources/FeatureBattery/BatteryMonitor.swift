import AppKit
import Foundation
import IOKit.ps
import HashDIslandKit

/// A transient battery moment the island announces like the iPhone does:
/// plugging in shows a brief charge pill; dropping through 20% / 10% warns.
public enum BatteryEvent: Equatable {
    case startedCharging(Int)
    case lowBattery(Int)
    /// Reached full, or reached the level macOS is holding it at.
    case fullyCharged(Int)
    /// Unplugged — the counterpart to plugging in, so the pair reads as one
    /// idea rather than an announcement that only ever happens in one
    /// direction.
    case unplugged(Int)

    /// A warning is worth interrupting for and worth reading twice; the rest
    /// are pleasantries and should leave quickly. Package-visible so the checks
    /// can pin which announcements earn the longer stay.
    package var isWarning: Bool {
        if case .lowBattery = self { return true }
        return false
    }
}

/// What the battery is doing, as the iPhone distinguishes it.
///
/// "Plugged in" and "charging" are not the same thing and macOS separates them
/// for a real reason: optimised charging parks the battery at around 80% for
/// its health, and Macs on permanent desk power sit there for weeks. Showing a
/// charging bolt for that is a small lie that makes people think something is
/// broken, so the state that says "connected, deliberately not filling" exists
/// on its own.
public enum BatteryState: Equatable {
    case discharging
    case charging
    /// On power, at 100%.
    case charged
    /// On power, deliberately not charging — usually optimised charging.
    case onHold
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
    /// What the battery is doing — charging, held, full, or on its own.
    @Published public private(set) var state: BatteryState = .discharging
    /// Minutes until full while charging, when macOS is willing to estimate.
    @Published public private(set) var minutesToFull: Int?
    /// Whether macOS Low Power Mode is on. Read-only: macOS offers no public
    /// way to switch it, so the app reports it and can open the pane that does.
    @Published public private(set) var isLowPowerMode: Bool = false

    private var sampler: PollingSampler?
    private weak var presence: LivePresence?
    private var powerSource: CFRunLoopSource?
    private var eventWork: DispatchWorkItem?
    private var lowPowerObserver: NSObjectProtocol?
    private var lastCharging: Bool?
    private var lastPercentage: Int?
    private var lastState: BatteryState?

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

        // Low Power Mode announces its own changes, so it never needs polling —
        // including when the user turns it on from the pane this app can open
        // for them, or when macOS turns it on by itself at 20%.
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                if self.isLowPowerMode != enabled { self.isLowPowerMode = enabled }
            }
        }

        // IOKit above reports every real change — plugged in, unplugged, each
        // step down — the instant it happens, so this poll is only a backstop
        // behind it. It does not need to be brisk, and a battery readout is the
        // last thing that should be spending battery.
        sampler = PollingSampler(interval: 60.0) { [weak self] in self?.sample() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
            self.lowPowerObserver = nil
        }
        eventWork?.cancel()
        eventWork = nil
        event = nil
        presence?.setActive("battery", false)
    }

    /// Opens System Settings at the Battery pane.
    ///
    /// The default route to Low Power Mode, and the one that costs nothing.
    /// macOS has no public API to switch it, so this is one click from the
    /// panel to the switch that owns it.
    public static func openEnergySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Switches Low Power Mode directly, at the cost of an administrator
    /// password prompt. Only ever called when the user has opted in.
    ///
    /// `pmset` is the only thing on macOS that can set this and it requires
    /// root, so there is no version of this that happens quietly. The prompt is
    /// macOS's own — the password goes to the system's authorisation service
    /// and never passes through this app, which is the reason this is done with
    /// a one-shot privileged command rather than by installing a helper that
    /// would hold that privilege for the life of the app.
    ///
    /// The command is fixed text with a single interpolated 0 or 1 derived from
    /// a Bool, so there is nothing here a caller could steer.
    public static func setLowPowerMode(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        let value = enabled ? 1 : 0
        let script = """
        do shell script "/usr/bin/pmset -a lowpowermode \(value)" with administrator privileges
        """
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let ok = NSAppleScript(source: script)?.executeAndReturnError(&error) != nil && error == nil
            if let error {
                // A cancelled password prompt is a decision, not a fault, and
                // reporting it as one would be noise on every second use.
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                if code != -128 {
                    FileHandle.standardError.write(Data(
                        "Hash D Island: could not change Low Power Mode — \(error)\n".utf8
                    ))
                }
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// The low-battery threshold (20 or 10) that `new` crossed downward from
    /// `old`, if any. Pure so the checks can pin the behavior.
    package static func crossedLowThreshold(from old: Int, to new: Int) -> Int? {
        for threshold in [10, 20] where old > threshold && new <= threshold {
            return threshold
        }
        return nil
    }

    /// What the battery is doing, from the three things IOKit reports.
    ///
    /// Pure and package-visible so the checks can pin every combination without
    /// a Mac in that state — "plugged in at 80% and deliberately not charging"
    /// being the one that is hard to produce on demand and easy to get wrong.
    package static func state(
        onPower: Bool,
        isCharging: Bool,
        percentage: Int
    ) -> BatteryState {
        guard onPower else { return .discharging }
        if isCharging { return .charging }
        return percentage >= 95 ? .charged : .onHold
    }

    /// How long an announcement stays.
    ///
    /// A warning earns longer than a pleasantry. "Charging" is a courtesy the
    /// user already knows about — they just plugged the cable in — while 10%
    /// is the one message in the app that must not be missed, and it is worth
    /// the extra seconds even on a surface built for glances.
    private static let noticeSeconds: TimeInterval = 4
    private static let warningSeconds: TimeInterval = 8

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
        let seconds = newEvent.isWarning ? Self.warningSeconds : Self.noticeSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
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

            // Being on power and being charged BY it are separate facts, and
            // only IsCharging answers the second. Falling back to the power
            // state when it is missing is what made a Mac parked at 80% by
            // optimised charging claim it was charging.
            let onPower = (description[kIOPSPowerSourceStateKey as String] as? String)
                == kIOPSACPowerValue
            let newCharging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false

            let timeToEmpty = description[kIOPSTimeToEmptyKey as String] as? Int
            let newRemaining = (timeToEmpty ?? -1) > 0 ? timeToEmpty : nil
            let timeToFull = description[kIOPSTimeToFullChargeKey as String] as? Int
            let newToFull = (timeToFull ?? -1) > 0 ? timeToFull : nil

            let newState = Self.state(
                onPower: onPower, isCharging: newCharging, percentage: newPercentage
            )

            // Transient announcements. Each fires on a real transition rather
            // than on a level, so none of them can repeat while nothing moves.
            if let previous = lastState, previous != newState {
                switch newState {
                case .charging where previous == .discharging:
                    announce(.startedCharging(newPercentage))
                case .charged, .onHold:
                    // Only worth saying when it just got there by charging.
                    if previous == .charging { announce(.fullyCharged(newPercentage)) }
                case .discharging:
                    announce(.unplugged(newPercentage))
                default:
                    break
                }
            }
            if !onPower, let lastPct = lastPercentage,
               Self.crossedLowThreshold(from: lastPct, to: newPercentage) != nil {
                announce(.lowBattery(newPercentage))
            }
            lastCharging = newCharging
            lastPercentage = newPercentage
            lastState = newState

            // Assign only on real change so identical samples cause no redraws.
            if percentage != newPercentage { percentage = newPercentage }
            if isCharging != newCharging { isCharging = newCharging }
            if state != newState { state = newState }
            if minutesRemaining != newRemaining { minutesRemaining = newRemaining }
            if minutesToFull != newToFull { minutesToFull = newToFull }
            if !hasBattery { hasBattery = true }
            return
        }

        if hasBattery { hasBattery = false }
    }
}
