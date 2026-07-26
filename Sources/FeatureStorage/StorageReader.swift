import Foundation

/// How full the startup disk is.
public struct DiskUsage: Equatable {
    /// The volume's name, as Finder shows it.
    public let name: String
    public let totalBytes: Int64
    /// Free right now: the one figure Finder, `df` and `diskutil` all agree on.
    ///
    /// Deliberately NOT
    /// `volumeAvailableCapacityForImportantUsageKey`. That key answers a
    /// different question — "how much could I write if I really had to" — and
    /// it counts room macOS believes it could make by evicting and purging. On
    /// the Mac this was corrected against it returned **229.95 GB on a 245 GB
    /// disk holding 180 GB of data**, i.e. it offered up more room than the
    /// volume had files. Driving "% full" from it reported a disk that was 74%
    /// full as **7% full**, which is not a rounding error but the wrong
    /// question answered confidently.
    public let freeBytes: Int64

    public init(name: String, totalBytes: Int64, freeBytes: Int64) {
        let total = max(0, totalBytes)
        self.name = name
        self.totalBytes = total
        // A disk cannot have more free than it has, whatever the system says.
        self.freeBytes = min(max(0, freeBytes), total)
    }

    /// Everything not free right now — apps, files, and system data alike.
    public var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

    /// Whole percent used, 0 to 100. Zero when the volume reports no size,
    /// rather than a division by nothing.
    public var percentUsed: Int {
        guard totalBytes > 0 else { return 0 }
        return Int((Double(usedBytes) / Double(totalBytes) * 100).rounded())
    }

    /// The bar's parts, in order, each as a fraction of the disk.
    ///
    /// Always sums to exactly one, because the two quantities are defined
    /// against each other rather than measured separately: free is what the
    /// volume reports, and taken is the rest. Nothing here can drift apart
    /// between samples the way independently measured parts would.
    public var segments: [(fraction: Double, kind: Segment)] {
        guard totalBytes > 0 else { return [] }
        let total = Double(totalBytes)
        return [
            (Double(usedBytes) / total, .taken),
            (Double(freeBytes) / total, .free),
        ]
    }

    public enum Segment: String, CaseIterable, Sendable {
        case taken
        case free

        public var label: String {
            switch self {
            case .taken: return "In use"
            case .free: return "Free"
            }
        }

        public var detail: String {
            switch self {
            case .taken: return "Apps, files and system data."
            case .free: return "Available right now."
            }
        }
    }
}

/// Reads the startup disk's capacity from the public file-system API.
///
/// **Which "free" — the correction this file exists to record.** macOS offers
/// two, and they are not two shades of the same answer:
///
///   * `volumeAvailableCapacity` — free right now. Agrees with `df`, with
///     `diskutil`'s container free space, and with the number a person gets by
///     subtracting what they know they have.
///   * `volumeAvailableCapacityForImportantUsage` — what could be *made* free
///     for something the system deems important, counting room it believes it
///     could win back by purging caches and evicting files.
///
/// This readout used the second, on the reasoning that it is "the number Finder
/// shows". Measured, that was simply wrong. On a 245 GB disk whose five APFS
/// volumes consume 180 GB (157 GB of it the Data volume), it returned
/// **229.95 GB available** — more room than the disk has files — and the panel
/// therefore announced a 74%-full disk as **7% full, 228 GB free**. There were
/// no local snapshots to explain it; the key is answering a question the panel
/// was not asking. A readout whose whole promise is that you can check it must
/// use the figure every other tool on the Mac would corroborate.
///
/// Apple's own Storage pane is not a tiebreaker here: it reports "14.99 GB of
/// 245.11 GB used" while listing categories that sum far past that, so it is
/// showing the sealed system volume's usage above a breakdown of the data
/// volume. `diskutil apfs list` is the thing that reconciles — per-volume
/// consumption summing to container total minus container free, exactly.
///
/// **No reclaimable band.** The gap between the two figures used to be drawn as
/// a middle segment named "Reclaimable", on the reasoning that naming it is
/// most of the help. On this machine that gap was 165 GB — more than the Data
/// volume holds in total — so the band was inviting people to believe two
/// thirds of their disk was about to come back. The figure cannot be
/// corroborated by anything else on the system, and this file's own standard is
/// that a plausible-looking wrong number is worse than none. The bar is now
/// simply what is used and what is free.
///
/// **No category breakdown.** Deliberately not attempted, and this is unchanged:
/// there is no cheap API for it, splitting macOS from your own files is not
/// available through `statfs` (both volumes report the whole container), and
/// every remaining honest route is a full walk of the disk or a permission
/// prompt for folders this app has no other reason to open. macOS already has a
/// screen that does it properly and that you can act on, so the panel offers a
/// way there instead.
package enum StorageReader {
    package static let volumeURL = URL(fileURLWithPath: "/")

    static func read() -> DiskUsage? {
        read(volume: volumeURL)
    }

    package static func read(volume: URL) -> DiskUsage? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }

        return DiskUsage(
            name: values.volumeName ?? "Startup disk",
            totalBytes: Int64(total),
            freeBytes: Int64(values.volumeAvailableCapacity ?? 0)
        )
    }
}
