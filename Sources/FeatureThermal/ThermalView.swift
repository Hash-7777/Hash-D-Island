import SwiftUI
import HashNotchKit

/// Compact thermal-pressure readout with a thermometer glyph tinted by pressure.
struct ThermalView: View {
    @ObservedObject var monitor: ThermalMonitor
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(monitor.label)
                .foregroundStyle(theme.textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.pillBackground)
        )
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
