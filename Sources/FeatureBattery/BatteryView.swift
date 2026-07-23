import SwiftUI
import HashDIslandKit

/// Compact battery readout. The style selects icon, percent, both, or the
/// estimated time remaining.
struct BatteryView: View {
    @ObservedObject var monitor: BatteryMonitor
    let theme: Theme
    let style: BatteryStyle

    var body: some View {
        HStack(spacing: 6) {
            if style != .percent {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(symbolColor)
            }
            if let text = valueText {
                Text(text)
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: monitor.percentage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.pillBackground)
        )
        .opacity(monitor.hasBattery ? 1 : 0.4)
    }

    private var valueText: String? {
        switch style {
        case .icon:
            return nil
        case .percent, .iconAndPercent:
            return "\(monitor.percentage)%"
        case .timeRemaining:
            if let minutes = monitor.minutesRemaining, minutes > 0 {
                return Formatters.hoursMinutes(minutes)
            }
            return "\(monitor.percentage)%"
        }
    }

    private var symbolName: String {
        switch monitor.state {
        case .charging: return "bolt.fill"
        case .charged: return "battery.100percent.bolt"
        case .onHold: return "battery.100percent.bolt"
        case .discharging: return "battery.100"
        }
    }

    /// Low Power Mode paints the battery yellow, exactly as it does on iPhone,
    /// because the single most useful thing that indicator can say is "the
    /// reason this feels different is a setting, not a fault".
    private var symbolColor: Color {
        if monitor.isLowPowerMode { return .yellow }
        switch monitor.state {
        case .charging, .charged, .onHold: return theme.downColor
        case .discharging: return fillColor
        }
    }

    private var fillColor: Color {
        switch monitor.percentage {
        case ..<20: return theme.upColor
        case ..<50: return .orange
        default: return theme.downColor
        }
    }
}

/// Compact-live: a brief iPhone-style announcement flanking the notch when
/// the Mac starts charging or the battery runs low.
struct BatteryEventIconView: View {
    @ObservedObject var monitor: BatteryMonitor
    let theme: Theme

    var body: some View {
        if let event = monitor.event {
            Image(systemName: iconName(event))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor(event))
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func iconName(_ event: BatteryEvent) -> String {
        switch event {
        case .pluggedIn: return monitor.state == .onHold ? "pause.circle.fill" : "bolt.fill"
        case .lowBattery: return "exclamationmark.triangle.fill"
        case .fullyCharged: return "checkmark.circle.fill"
        case .unplugged: return "powerplug"
        }
    }

    private func iconColor(_ event: BatteryEvent) -> Color {
        switch event {
        case .pluggedIn, .fullyCharged: return theme.downColor
        case .lowBattery: return theme.upColor
        case .unplugged: return theme.subtitleColor
        }
    }
}

struct BatteryEventTextView: View {
    @ObservedObject var monitor: BatteryMonitor
    let theme: Theme

    var body: some View {
        if let event = monitor.event {
            Text(text(event))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .lineLimit(1)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func text(_ event: BatteryEvent) -> String {
        switch event {
        case .pluggedIn(let percent):
            // Read from the LIVE state rather than from the moment the cable
            // went in. macOS needs a second to settle on whether this is a
            // charge, a health hold, or nothing to do — and because this view
            // observes the monitor, the line rewrites itself in place as that
            // answer arrives, rather than committing to a guess and being wrong
            // for the four seconds it is on screen.
            switch monitor.state {
            case .charged:
                return "Charged · \(percent)%"
            case .onHold:
                return "Plugged in · \(percent)% · held for battery health"
            case .charging, .discharging:
                // The cable is the part you can see. The time to full, and
                // whether what you grabbed will actually get you there, is the
                // part you cannot.
                var parts = ["\(monitor.chargeSpeed?.label ?? "Charging") · \(percent)%"]
                if let watts = monitor.adapterWatts, watts > 0 { parts.append("\(watts)W") }
                if let minutes = monitor.minutesToFull, minutes > 0 {
                    parts.append("\(Formatters.hoursMinutes(minutes)) to full")
                }
                return parts.joined(separator: " · ")
            }
        case .lowBattery(let percent):
            // Says what to do, not just what happened. Low Power Mode is the
            // one action that buys real time, and on a Mac it lives one click
            // away in the panel rather than on the strip, which takes no clicks.
            return percent <= 10
                ? "Battery \(percent)% · plug in soon"
                : "Battery \(percent)% · Low Power Mode helps"
        case .fullyCharged(let percent):
            return percent >= 95 ? "Fully charged" : "Charged to \(percent)%"
        case .unplugged(let percent):
            if let minutes = monitor.minutesRemaining, minutes > 0 {
                return "On battery · \(percent)% · \(Formatters.hoursMinutes(minutes)) left"
            }
            return "On battery · \(percent)%"
        }
    }
}

/// Expanded detail: battery as a clean row that matches the panel, plus the
/// one action worth offering when it is running out.
struct BatteryDetailView: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject var settings: SettingsStore
    let theme: Theme
    @State private var working = false

    /// When the Low Power Mode line appears: while it is on (so it is never a
    /// mystery why the Mac feels slower), and while the battery is low enough
    /// for it to be the obvious next move. The rest of the time it would just
    /// be another row between the user and the numbers they opened the panel
    /// for.
    private var showsLowPowerRow: Bool {
        monitor.isLowPowerMode || (monitor.state == .discharging && monitor.percentage <= 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotchRow("Battery", theme: theme) {
                HStack(spacing: 6) {
                    if let symbol = stateSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(stateColor)
                    }
                    if let detail = detailText {
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.subtitleColor)
                    }
                    Text("\(monitor.percentage)%")
                        .foregroundStyle(monitor.isLowPowerMode ? .yellow : theme.textColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            if showsLowPowerRow { lowPowerRow }
        }
        .animation(.snappy, value: monitor.percentage)
        .animation(.snappy, value: monitor.isLowPowerMode)
    }

    /// Low Power Mode, by whichever route the user has chosen.
    ///
    /// By default this opens the Battery pane, because macOS offers no public
    /// way to switch the setting and the only thing that can needs root. Turn
    /// on "Switch Low Power Mode from the panel" in Settings and the row
    /// becomes a real toggle that asks macOS for an administrator password each
    /// time — worth it to some people, a nasty surprise to everyone else, which
    /// is why it is opt-in rather than a judgement made on their behalf.
    private var lowPowerRow: some View {
        Button(action: activate) {
            HStack(spacing: 6) {
                Image(systemName: "battery.25")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textColor)
                Spacer(minLength: 6)
                if working {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: canSwitchDirectly ? "chevron.right" : "arrow.up.forward")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.subtitleColor)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.yellow.opacity(monitor.isLowPowerMode ? 0.16 : 0.10))
            )
            .frame(width: Panel.rowWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(working)
        .transition(.opacity.combined(with: .offset(y: -4)))
    }

    private var canSwitchDirectly: Bool { settings.canSwitchLowPowerMode }

    private var label: String {
        if working { return monitor.isLowPowerMode ? "Turning off…" : "Turning on…" }
        if monitor.isLowPowerMode {
            return canSwitchDirectly ? "Low Power Mode is on — turn off" : "Low Power Mode is on"
        }
        return "Turn on Low Power Mode"
    }

    private func activate() {
        guard canSwitchDirectly else {
            BatteryMonitor.openEnergySettings()
            return
        }
        working = true
        // The monitor is watching the system's own power-state notification, so
        // the new value arrives on its own — there is nothing to write back
        // here, and nothing to get out of step if the password prompt is
        // cancelled or the change is made somewhere else entirely.
        BatteryMonitor.setLowPowerMode(!monitor.isLowPowerMode) { _ in working = false }
    }

    private var stateSymbol: String? {
        switch monitor.state {
        case .charging: return "bolt.fill"
        case .charged: return "checkmark"
        case .onHold: return "pause.fill"
        case .discharging: return nil
        }
    }

    private var stateColor: Color {
        switch monitor.state {
        case .charging, .charged: return theme.downColor
        case .onHold: return theme.subtitleColor
        case .discharging: return theme.textColor
        }
    }

    private var detailText: String? {
        switch monitor.state {
        case .charging:
            // The two things you actually want while it fills: how long, and
            // whether the adapter to hand is up to the job.
            var parts: [String] = []
            if let minutes = monitor.minutesToFull, minutes > 0 {
                parts.append("\(Formatters.hoursMinutes(minutes)) to full")
            }
            if let watts = monitor.adapterWatts, watts > 0 {
                let speed = monitor.chargeSpeed.map { $0 == .standard ? "" : " \($0.label.lowercased())" } ?? ""
                parts.append("\(watts)W\(speed)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .charged:
            return nil
        case .onHold:
            // Naming the reason turns "why has it stopped at 80%?" into a
            // feature the user already half-knows about.
            return "held for battery health"
        case .discharging:
            guard let minutes = monitor.minutesRemaining, minutes > 0 else { return nil }
            return "\(Formatters.hoursMinutes(minutes)) left"
        }
    }
}
