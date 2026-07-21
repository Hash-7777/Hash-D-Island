import SwiftUI
import HashNotchKit

/// Compact battery readout. The style selects icon, percent, both, or the
/// estimated time remaining.
struct BatteryView: View {
    @ObservedObject var monitor: BatteryMonitor
    let theme: Theme
    let style: BatteryStyle

    var body: some View {
        HStack(spacing: 6) {
            if style != .percent {
                Image(systemName: monitor.isCharging ? "bolt.fill" : "battery.100")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(monitor.isCharging ? theme.downColor : fillColor)
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
                return String(format: "%d:%02d", minutes / 60, minutes % 60)
            }
            return "\(monitor.percentage)%"
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
