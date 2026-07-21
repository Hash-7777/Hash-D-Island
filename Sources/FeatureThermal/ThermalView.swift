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
                    .contentTransition(.numericText())
                    .animation(.snappy, value: monitor.hottestCelsius)
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
            NotchSectionHeader("TEMPERATURE", theme: theme)

            if monitor.sensors.isEmpty {
                NotchRow("Pressure", theme: theme) {
                    Text(monitor.pressureLabel).foregroundStyle(theme.textColor)
                }
            } else {
                ForEach(monitor.sensors.prefix(5)) { sensor in
                    NotchRow(sensor.name, theme: theme) {
                        Text("\(Int(sensor.celsius.rounded()))°")
                            .foregroundStyle(theme.textColor)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .animation(.snappy, value: sensor.celsius)
                }
            }
        }
    }
}
