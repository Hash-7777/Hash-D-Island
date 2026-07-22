import SwiftUI
import HashNotchKit

/// Compact-live: a small timer glyph left of the notch while counting down.
struct TimerIconView: View {
    @ObservedObject var engine: TimerEngine
    let theme: Theme

    var body: some View {
        switch engine.phase {
        case .running:
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
                .transition(.scale.combined(with: .opacity))
        case .finished:
            Image(systemName: "bell.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
                .transition(.scale.combined(with: .opacity))
        case .idle:
            EmptyView()
        }
    }
}

/// Compact-live: the countdown right of the notch.
struct TimerTextView: View {
    @ObservedObject var engine: TimerEngine
    let theme: Theme

    var body: some View {
        switch engine.phase {
        case .running:
            Text(TimerViews.clock(engine.secondsLeft(now: engine.now)))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .finished:
            Text("Time's up")
                .foregroundStyle(theme.textColor)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .idle:
            EmptyView()
        }
    }
}

/// Expanded detail: quick-start buttons when idle; countdown, progress, and
/// a stop button while running.
struct TimerDetailView: View {
    @ObservedObject var engine: TimerEngine
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchSectionHeader("TIMER", theme: theme)
            switch engine.phase {
            case .idle:
                HStack(spacing: 8) {
                    quickButton(5)
                    quickButton(15)
                    quickButton(25)
                    Spacer(minLength: 0)
                }
                .frame(width: Panel.rowWidth)
            case .running:
                HStack(spacing: 10) {
                    Text(TimerViews.clock(engine.secondsLeft(now: engine.now)))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.16))
                            Capsule()
                                .fill(Color.orange)
                                .frame(width: max(3, geo.size.width * engine.fractionDone(now: engine.now)))
                        }
                    }
                    .frame(height: 3)
                    stopButton
                }
                .frame(width: Panel.rowWidth)
            case .finished:
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("Time's up")
                        .foregroundStyle(theme.textColor)
                    Spacer(minLength: 0)
                    Button("OK") { engine.cancel() }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.subtitleColor)
                }
                .frame(width: Panel.rowWidth)
            }
        }
    }

    private func quickButton(_ minutes: Int) -> some View {
        Button("\(minutes) min") { engine.begin(minutes: minutes) }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.12)))
            .contentShape(Capsule())
    }

    private var stopButton: some View {
        Button {
            engine.cancel()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.subtitleColor)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

enum TimerViews {
    /// mm:ss (or h:mm:ss beyond an hour).
    static func clock(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
