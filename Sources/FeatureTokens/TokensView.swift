import SwiftUI
import HashNotchKit

/// Compact token readout: today's total AI tokens across your tools.
struct TokensView: View {
    @ObservedObject var monitor: TokensMonitor
    let theme: Theme
    let style: TokensStyle

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.accent)
            Text(Formatters.compactCount(monitor.today.total))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .contentTransition(.numericText())
            if style == .labeled {
                Text("today")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.subtitleColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(theme.pillBackground))
        .animation(.snappy, value: monitor.today.total)
    }
}

/// Expanded detail: today's tokens broken down by source.
struct TokensDetailView: View {
    @ObservedObject var monitor: TokensMonitor
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI TOKENS TODAY")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.subtitleColor)

            row("Total", monitor.today.total, emphasized: true)
            row("Claude Code", monitor.today.claude)
            row("HashCortx", monitor.today.hashCortx)
            row("HashCerebrum", monitor.today.hashCerebrum)
        }
    }

    private func row(_ label: String, _ value: Int64, emphasized: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(emphasized ? theme.textColor : theme.subtitleColor)
            Spacer(minLength: 8)
            Text(Formatters.compactCount(value))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .fontWeight(emphasized ? .bold : .regular)
        }
        .frame(width: 200, alignment: .leading)
        .animation(.snappy, value: value)
    }
}
