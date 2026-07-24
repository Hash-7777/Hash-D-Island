import SwiftUI
import HashDIslandKit

/// Expanded detail: processor load as a number, a graph, or both.
struct CPUDetailView: View {
    @ObservedObject var monitor: CPUMonitor
    let theme: Theme
    let style: CPUStyle

    var body: some View {
        NotchRow("CPU", theme: theme) {
            HStack(spacing: 8) {
                if style != .number {
                    Sparkline(values: monitor.history, tint: tint)
                        .frame(width: 62, height: 16)
                }
                if style != .graph {
                    Text(text)
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
        }
        .animation(.snappy, value: monitor.load)
    }

    /// A dash until there are two readings to compare. Better than a confident
    /// 0% for a processor that is plainly doing something.
    private var text: String {
        guard let load = monitor.load else { return "—" }
        return "\(Int((load * 100).rounded()))%"
    }

    private var tint: Color {
        switch monitor.load ?? 0 {
        case 0.85...: return theme.upColor
        case 0.6...: return .orange
        default: return theme.accent
        }
    }
}
