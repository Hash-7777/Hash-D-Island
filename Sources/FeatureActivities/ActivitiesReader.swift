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
enum ActivitiesReader {
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
        guard let data = try? Data(contentsOf: feedURL),
              let items = try? JSONDecoder().decode([ActivityDTO].self, from: data) else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        return items.map { dto in
            LiveActivity(
                id: dto.id,
                icon: dto.icon ?? "app.badge",
                title: dto.title,
                subtitle: dto.subtitle,
                progress: dto.progress,
                endsAt: dto.endsAt.flatMap { formatter.date(from: $0) }
            )
        }
        .filter { !$0.isExpired }
    }
}
