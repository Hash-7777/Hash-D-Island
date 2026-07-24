import SwiftUI
import HashDIslandKit

/// Expanded detail: how full the disk is, and what the room is going on.
struct StorageDetailView: View {
    @ObservedObject var monitor: StorageMonitor
    let theme: Theme

    var body: some View {
        if let usage = monitor.usage {
            VStack(alignment: .leading, spacing: 7) {
                // "STORAGE", not the volume's name. Almost every Mac's startup
                // disk is still called Macintosh HD, which names the hardware
                // rather than the thing being reported and reads as a label
                // nobody got round to changing.
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

                bar(usage)
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
            .animation(.snappy, value: usage.percentUsed)
        }
    }

    /// One bar in three parts rather than a single fill: what is genuinely
    /// taken, what macOS would hand back if something needed the room, and what
    /// is free right now.
    ///
    /// The parts are not labelled underneath. This is a glanceable panel with
    /// eleven other indicators in it, and three more lines of legend cost more
    /// height than the words were worth — the percentage above already says how
    /// full, and the figure beside it already says how much is left. The middle
    /// band is the only thing the bar adds that no number here states, so it is
    /// named in the tooltip rather than given a row of its own.
    private func bar(_ usage: DiskUsage) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(usage.segments, id: \.kind) { segment in
                    Rectangle()
                        .fill(color(for: segment.kind))
                        .frame(width: max(0, geo.size.width * CGFloat(segment.fraction)))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 5)
        .help(tooltip(usage))
    }

    private func tooltip(_ usage: DiskUsage) -> String {
        usage.segments
            .filter { $0.fraction > 0.001 }
            .map { "\($0.kind.label): \(Formatters.bytes(Int64(Double(usage.totalBytes) * $0.fraction)))" }
            .joined(separator: " · ")
    }

    private func color(for kind: DiskUsage.Segment) -> Color {
        switch kind {
        case .taken: return fill
        // Reclaimable is drawn as a lighter shade of taken rather than a colour
        // of its own: it IS taken right now, just not permanently, and giving it
        // an unrelated hue would read as a third kind of thing.
        case .reclaimable: return fill.opacity(0.35)
        case .free: return Color.white.opacity(0.12)
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
