import SwiftUI
import HashDIslandKit

/// Expanded detail: how full the disk is, as a number, a bar, and the figure
/// people actually check — how much room is left.
struct StorageDetailView: View {
    @ObservedObject var monitor: StorageMonitor
    let theme: Theme

    var body: some View {
        if let usage = monitor.usage {
            VStack(alignment: .leading, spacing: 7) {
                // "STORAGE", not the volume's name. Almost every Mac's startup
                // disk is still called Macintosh HD, which names the hardware
                // rather than the thing being reported, and reads as a label
                // someone forgot to change.
                NotchSectionHeader("STORAGE", theme: theme)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(usage.percentUsed)%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("full")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.subtitleColor)
                    Spacer(minLength: 8)
                    Text("\(Formatters.bytes(usage.availableBytes)) free")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.subtitleColor)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(fill)
                            .frame(width: max(3, geo.size.width * CGFloat(usage.percentUsed) / 100))
                    }
                }
                .frame(height: 4)
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
            .animation(.snappy, value: usage.percentUsed)
        }
    }

    /// Quiet until it matters. A disk at 70% is simply a disk; one with almost
    /// nothing left is the reason you opened the panel.
    private var fill: Color {
        switch monitor.usage?.percentUsed ?? 0 {
        case 90...: return theme.upColor
        case 75...: return .orange
        default: return theme.accent
        }
    }
}
