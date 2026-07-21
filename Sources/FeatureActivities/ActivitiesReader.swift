import Foundation

/// One live activity posted to HashNotch by another app, a script, or a
/// Shortcut. This is the macOS-honest version of iPhone Live Activities: since
/// no system API lets us read another app's activity, apps push to a local feed
/// and HashNotch renders it.
public struct LiveActivity: Identifiable, Equatable {
    public let id: String
    public let icon: String        // SF Symbol name, e.g. "bicycle"
    public let title: String
    public let subtitle: String?
    public let progress: Double?   // 0...1, optional bar
    public let endsAt: Date?       // optional countdown target

    /// Seconds remaining until `endsAt`, if set.
    public func secondsLeft(now: Date) -> Int? {
        guard let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(now)))
    }

    public var isExpired: Bool {
        guard let endsAt else { return false }
        return endsAt.timeIntervalSinceNow < -2
    }
}

/// Reads the activity feed file. Missing/empty/invalid file → no activities.
///
/// Feed: `~/.hashnotch/activities.json`, an array of objects:
///   {"id","icon","title","subtitle"?,"progress"?,"endsAt"? (ISO8601)}
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

    static var feedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hashnotch/activities.json")
    }

    private struct ActivityDTO: Decodable {
        let id: String
        let icon: String?
        let title: String
        let subtitle: String?
        let progress: Double?
        let endsAt: String?
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

            let activity = LiveActivity(
                id: id,
                icon: dto.icon ?? "app.badge",
                title: title,
                subtitle: dto.subtitle.map { String($0.prefix(maxTextLength)) },
                progress: dto.progress.map { min(max($0, 0), 1) },
                endsAt: dto.endsAt.flatMap(parseDate)
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
