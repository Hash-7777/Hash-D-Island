import Foundation

/// One live activity posted to Hash D Island by another app, a script, or a
/// Shortcut. This is the macOS-honest version of iPhone Live Activities: since
/// no system API lets us read another app's activity, apps push to a local feed
/// and Hash D Island renders it.
public struct LiveActivity: Identifiable, Equatable {
    public let id: String
    public let icon: String        // SF Symbol name, e.g. "bicycle"
    public let title: String
    public let subtitle: String?
    public let progress: Double?   // 0...1, optional bar
    public let endsAt: Date?       // optional countdown target
    /// How long to show this for, counted from the moment it first appears.
    ///
    /// Set this instead of `endsAt` for something that has already happened —
    /// a job that finished, a file that arrived. Those are announcements, not
    /// countdowns: no timer is drawn, and the notice leaves on its own. A
    /// number counting down next to "finished" only ever asked the reader to
    /// watch something that was already over.
    public let dismissAfter: TimeInterval?

    public init(
        id: String,
        icon: String,
        title: String,
        subtitle: String?,
        progress: Double?,
        endsAt: Date?,
        dismissAfter: TimeInterval?
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.endsAt = endsAt
        self.dismissAfter = dismissAfter
    }

    /// True when this counts down to something, rather than announcing
    /// something that already happened. Only a countdown draws a timer.
    public var showsCountdown: Bool { endsAt != nil && dismissAfter == nil }

    /// Seconds remaining until `endsAt`, if this is a countdown.
    public func secondsLeft(now: Date) -> Int? {
        guard showsCountdown, let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(now)))
    }

    public var isExpired: Bool {
        guard let endsAt else { return false }
        return endsAt.timeIntervalSinceNow < -2
    }

    /// When a self-dismissing notice should disappear, given the moment it was
    /// first seen. Nil for everything else.
    ///
    /// `preferred` is the reader's own choice of how long a notice should stay.
    /// It wins over the poster's suggestion: whoever wrote the feed knows what
    /// happened, but only the person looking at the notch knows how long they
    /// want it there.
    public func dismissalDate(firstSeen: Date, preferring preferred: TimeInterval? = nil) -> Date? {
        guard dismissAfter != nil else { return nil }
        return firstSeen.addingTimeInterval(preferred ?? dismissAfter ?? 0)
    }
}

/// Reads the activity feed file. Missing/empty/invalid file → no activities.
///
/// Feed: `~/.hashdisland/activities.json`, an array of objects:
///   {"id","icon","title","subtitle"?,"progress"?,"endsAt"? (ISO8601),
///    "dismissAfter"? (seconds)}
///
/// The feed is written by other processes, so everything is bounded before it
/// reaches the UI: the file itself, the number of activities, text lengths,
/// and the progress range. Duplicate ids keep their first occurrence (SwiftUI
/// list identity requires unique ids).
package enum ActivitiesReader {
    /// A feed is a handful of small objects; refuse anything absurdly larger.
    package static let maxFeedBytes = 262_144
    /// The notch is a glanceable surface, not a task manager.
    package static let maxActivities = 8
    private static let maxTextLength = 200
    /// SF Symbol names are short; an unknown name simply draws nothing, but the
    /// length is bounded like every other field so no string from the feed
    /// reaches the UI unmeasured.
    private static let maxIconLength = 64

    static var feedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hashdisland/activities.json")
    }

    /// A notice is glanceable, so its lifetime is clamped rather than trusted:
    /// long enough to read, never long enough to sit on the notch.
    private static let minDismissAfter: TimeInterval = 1
    private static let maxDismissAfter: TimeInterval = 30

    private struct ActivityDTO: Decodable {
        let id: String
        let icon: String?
        let title: String
        let subtitle: String?
        let progress: Double?
        let endsAt: String?
        let dismissAfter: Double?
    }

    static func read() -> [LiveActivity] {
        read(from: feedURL)
    }

    package static func read(from url: URL) -> [LiveActivity] {
        guard let data = try? Data(contentsOf: url),
              data.count <= maxFeedBytes,
              let items = try? JSONDecoder().decode([ActivityDTO].self, from: data) else {
            return []
        }

        var seen = Set<String>()
        var result: [LiveActivity] = []
        for dto in items {
            guard result.count < maxActivities else { break }
            let id = String(dto.id.prefix(maxTextLength))
            let title = String(dto.title.prefix(maxTextLength))
            guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { continue }

            // A missing OR empty icon falls back to the generic badge, so an
            // activity always has something to draw.
            let icon = dto.icon.map { String($0.prefix(maxIconLength)) } ?? ""

            let activity = LiveActivity(
                id: id,
                icon: icon.isEmpty ? "app.badge" : icon,
                title: title,
                subtitle: dto.subtitle.map { String($0.prefix(maxTextLength)) },
                progress: dto.progress.map { min(max($0, 0), 1) },
                endsAt: dto.endsAt.flatMap(parseDate),
                dismissAfter: dto.dismissAfter.map {
                    min(max($0, minDismissAfter), maxDismissAfter)
                }
            )
            if !activity.isExpired { result.append(activity) }
        }
        return result
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterFractional.date(from: string)
    }
}
