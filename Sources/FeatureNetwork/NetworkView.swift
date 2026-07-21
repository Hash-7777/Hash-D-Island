import SwiftUI
import HashNotchKit

/// Compact up/down throughput readout, echoing the reference HUD's red-up /
/// green-down styling.
struct NetworkView: View {
    @ObservedObject var monitor: NetworkMonitor
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            metric(systemImage: "arrow.up", rate: monitor.uploadBytesPerSec, color: theme.upColor)
            metric(systemImage: "arrow.down", rate: monitor.downloadBytesPerSec, color: theme.downColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.pillBackground)
        )
    }

    private func metric(systemImage: String, rate: Double, color: Color) -> some View {
        let formatted = Formatters.rate(rate)
        return HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(formatted.value)
                .foregroundStyle(theme.textColor)
            Text(formatted.unit)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.subtitleColor)
        }
        .monospacedDigit()
    }
}
