import SwiftUI
import AppKit
import HashDIslandKit

/// Expanded detail: how full the disk is, what is taking the room, and the
/// figure people actually check — how much is left.
struct StorageDetailView: View {
    @ObservedObject var monitor: StorageMonitor
    let theme: Theme
    let style: StorageStyle

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

                if style == .breakdown {
                    legend(usage)
                }
            }
            .frame(width: Panel.rowWidth, alignment: .leading)
            .animation(.snappy, value: usage.percentUsed)
        }
    }

    /// One bar in four parts rather than a single fill, so the question the
    /// readout is actually asked — where has it all gone — is answered in the
    /// same glance as how full it is.
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
    }

    private func legend(_ usage: DiskUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(usage.segments, id: \.kind) { segment in
                if segment.fraction > 0.001 {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: segment.kind))
                            .frame(width: 5, height: 5)
                        Text(segment.kind.label)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.subtitleColor)
                        Spacer(minLength: 8)
                        Text(Formatters.bytes(Int64(Double(usage.totalBytes) * segment.fraction)))
                            .font(.system(size: 9))
                            .foregroundStyle(
                                segment.kind == .taken ? theme.textColor : theme.subtitleColor
                            )
                            .monospacedDigit()
                    }
                    .help(segment.kind.detail)
                }
            }

            // Anything finer than this needs either a full walk of the disk or a
            // permission prompt for folders the app has no other reason to open.
            // macOS already has a screen that does it properly, and — the part
            // that matters — one you can act on. Sending people there beats
            // guessing at it here.
            Button("Manage in System Settings") {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage")
                else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.accent)
            .padding(.top, 1)
        }
    }

    /// Quiet until it matters. A disk at 70% is simply a disk; one with almost
    /// nothing left is the reason you opened the panel.
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

    private var fill: Color {
        switch monitor.usage?.percentUsed ?? 0 {
        case 90...: return theme.upColor
        case 75...: return .orange
        default: return theme.accent
        }
    }
}
