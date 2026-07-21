import SwiftUI
import HashNotchKit

/// Compact up/down throughput readout in a fixed MB/s layout.
///
/// Every element has a reserved width and the digits are monospaced, so the
/// arrows, numbers, and unit never shift as the values change — the readout
/// stays rock-steady in place. The style controls which directions appear.
struct NetworkView: View {
    @ObservedObject var monitor: NetworkMonitor
    let theme: Theme
    let style: NetworkStyle

    // Reserved widths keep the layout from reflowing as numbers change.
    private let valueWidth: CGFloat = 52
    private let unitWidth: CGFloat = 34
    private let iconWidth: CGFloat = 12

    var body: some View {
        HStack(spacing: 16) {
            if style != .downloadOnly {
                metric(systemImage: "arrow.up", rate: monitor.uploadBytesPerSec, color: theme.upColor)
            }
            if style != .uploadOnly {
                metric(systemImage: "arrow.down", rate: monitor.downloadBytesPerSec, color: theme.downColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(theme.pillBackground)
        )
        .fixedSize()
    }

    private func metric(systemImage: String, rate: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: iconWidth, alignment: .center)
            Text(Formatters.megabytesPerSecond(rate))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .frame(width: valueWidth, alignment: .trailing)
            Text(Formatters.megabytesUnit)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.subtitleColor)
                .frame(width: unitWidth, alignment: .leading)
        }
    }
}
