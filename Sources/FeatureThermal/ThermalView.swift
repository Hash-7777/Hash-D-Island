import SwiftUI
import HashNotchKit

/// Compact thermal readout: a thermometer glyph tinted by pressure, plus the
/// hottest die temperature (falling back to the pressure word).
struct ThermalView: View {
    @ObservedObject var monitor: ThermalMonitor
    let theme: Theme
    let style: ThermalStyle

    var body: some View {
        HStack(spacing: 6) {
            if style != .number {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            }
            if let text = valueText {
                Text(text)
                    .foregroundStyle(theme.textColor)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.pillBackground)
        )
    }

    private var valueText: String? {
        switch style {
        case .symbol:
            return nil
        case .word:
            return monitor.pressureLabel
        case .number, .symbolAndNumber:
            return monitor.compactText
        }
    }

    private var tint: Color {
        switch monitor.state {
        case .nominal: return theme.downColor
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return theme.upColor
        @unknown default: return theme.subtitleColor
        }
    }
}

/// Expanded detail: the top temperature sensors, shown when the HUD opens.
struct ThermalDetailView: View {
    @ObservedObject var monitor: ThermalMonitor
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TEMPERATURE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.subtitleColor)

            if monitor.sensors.isEmpty {
                Text(monitor.pressureLabel)
                    .foregroundStyle(theme.textColor)
            } else {
                ForEach(monitor.sensors.prefix(5)) { sensor in
                    HStack(spacing: 12) {
                        Text(sensor.name)
                            .foregroundStyle(theme.subtitleColor)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(Int(sensor.celsius.rounded()))°")
                            .foregroundStyle(theme.textColor)
                            .monospacedDigit()
                    }
                    .frame(width: 190, alignment: .leading)
                }
            }
        }
    }
}
