import SwiftUI
import HashNotchKit

/// Compact battery readout: a bolt when charging, the percentage, and a small
/// fill bar tinted by how much charge is left.
struct BatteryView: View {
    @ObservedObject var monitor: BatteryMonitor
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: monitor.isCharging ? "bolt.fill" : "battery.100")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(monitor.isCharging ? theme.downColor : fillColor)
            Text("\(monitor.percentage)%")
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.pillBackground)
        )
        .opacity(monitor.hasBattery ? 1 : 0.4)
    }

    private var fillColor: Color {
        switch monitor.percentage {
        case ..<20: return theme.upColor
        case ..<50: return .orange
        default: return theme.downColor
        }
    }
}
