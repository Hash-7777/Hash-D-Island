import Foundation

/// Tracks which features currently have something "live" to show always-on
/// (media playing, an activity in progress). When anything is live, the island
/// shows a slim compact strip below the notch even without hovering — like the
/// iPhone's compact Dynamic Island. Features signal in; the island observes.
@MainActor
public final class LivePresence: ObservableObject {
    @Published public private(set) var activeIDs: Set<String> = []

    public init() {}

    public var hasLive: Bool { !activeIDs.isEmpty }

    public func setActive(_ id: String, _ active: Bool) {
        if active {
            if !activeIDs.contains(id) { activeIDs.insert(id) }
        } else {
            if activeIDs.contains(id) { activeIDs.remove(id) }
        }
    }
}
