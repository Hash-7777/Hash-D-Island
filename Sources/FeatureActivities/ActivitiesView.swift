import SwiftUI
import HashNotchKit

/// Leading compact-live: the top activity's icon, to the left of the notch.
struct ActivitiesIconView: View {
    @ObservedObject var monitor: ActivitiesMonitor
    let theme: Theme

    var body: some View {
        if let activity = monitor.activities.first {
            Image(systemName: activity.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.accent)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Trailing compact-live: the top activity's title and time left, to the right.
struct ActivitiesTitleView: View {
    @ObservedObject var monitor: ActivitiesMonitor
    let theme: Theme

    var body: some View {
        if let activity = monitor.activities.first {
            HStack(spacing: 6) {
                Text(activity.title)
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                if let text = Formatters2.timeLeft(activity.secondsLeft(now: monitor.now)) {
                    Text(text)
                        .foregroundStyle(theme.subtitleColor)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: 150, alignment: .leading)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Expanded detail: every active activity as a row with a progress bar.
struct ActivitiesDetailView: View {
    @ObservedObject var monitor: ActivitiesMonitor
    let theme: Theme

    var body: some View {
        if !monitor.activities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                NotchSectionHeader("ACTIVITIES", theme: theme)
                ForEach(monitor.activities) { activity in
                    row(activity)
                }
            }
        }
    }

    private func row(_ activity: LiveActivity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: activity.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.title)
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)
                    if let subtitle = activity.subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.subtitleColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let text = Formatters2.timeLeft(activity.secondsLeft(now: monitor.now)) {
                    Text(text)
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                }
            }
            if let progress = activity.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(theme.accent)
                    .scaleEffect(x: 1, y: 0.7)
            }
        }
        .frame(width: Panel.rowWidth, alignment: .leading)
    }
}

/// Small local formatter (kept here to avoid growing the core for one feature).
enum Formatters2 {
    static func timeLeft(_ seconds: Int?) -> String? {
        guard let seconds else { return nil }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
