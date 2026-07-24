import Foundation

/// How full the startup disk is, and roughly what is taking the room.
public struct DiskUsage: Equatable {
    /// The volume's name, as Finder shows it.
    public let name: String
    public let totalBytes: Int64
    /// Free as macOS itself reports it — counting space it is willing to purge.
    /// This is the number Finder shows and the one people recognise.
    public let availableBytes: Int64
    /// Free right now, without macOS throwing anything away.
    public let plainAvailableBytes: Int64

    public init(
        name: String,
        totalBytes: Int64,
        availableBytes: Int64,
        plainAvailableBytes: Int64 = 0
    ) {
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.plainAvailableBytes = min(plainAvailableBytes, availableBytes)
    }

    /// Genuinely occupied — what would still be taken if macOS purged
    /// everything it is willing to.
    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    /// Space macOS is holding but would hand back if something needed it —
    /// caches, local snapshots, downloaded files it can fetch again.
    ///
    /// This is the whole reason Finder and `df` disagree about a disk, usually
    /// by tens of gigabytes, and why "the disk is full" and "there is nothing I
    /// can delete" are both true at once. Naming it is most of the help.
    public var purgeableBytes: Int64 {
        max(0, availableBytes - plainAvailableBytes)
    }

    /// Whole percent used, 0 to 100. Zero when the volume reports no size,
    /// rather than a division by nothing.
    public var percentUsed: Int {
        guard totalBytes > 0 else { return 0 }
        return Int((Double(usedBytes) / Double(totalBytes) * 100).rounded())
    }

    /// The bar's parts, in order, each as a fraction of the disk.
    ///
    /// Always sums to exactly one, because the three quantities are defined
    /// against each other rather than measured separately: taken is what is not
    /// free at all, reclaimable is the gap between the two free figures, and
    /// free is the smaller of them. Nothing here can drift apart between
    /// samples the way independently measured parts would.
    public var segments: [(fraction: Double, kind: Segment)] {
        guard totalBytes > 0 else { return [] }
        let total = Double(totalBytes)
        return [
            (Double(usedBytes) / total, .taken),
            (Double(purgeableBytes) / total, .reclaimable),
            (Double(plainAvailableBytes) / total, .free),
        ]
    }

    public enum Segment: String, CaseIterable, Sendable {
        case taken
        case reclaimable
        case free

        public var label: String {
            switch self {
            case .taken: return "In use"
            case .reclaimable: return "Reclaimable"
            case .free: return "Free"
            }
        }

        public var detail: String {
            switch self {
            case .taken: return "Apps, files and system data."
            case .reclaimable: return "Caches and snapshots macOS hands back when something needs the room."
            case .free: return "Available right now."
            }
        }
    }
}

/// Reads the startup disk's capacity from the public file-system API.
///
/// `volumeAvailableCapacityForImportantUsage` rather than the plain available
/// figure, because that is the number macOS itself shows: it counts space
/// currently held by things the system is willing to purge — caches, local
/// snapshots — as available, which is why Finder's number and `df` disagree by
/// tens of gigabytes and Finder's is the one people recognise. Both are read, so
/// the difference between them can be named rather than left as a mystery.
///
/// A finer breakdown — apps, documents, photos — is deliberately NOT attempted.
/// There is no cheap API for it. Splitting macOS from your own files looked
/// free, since APFS already keeps them on separate volumes, but `statfs`
/// reports the whole container for both and answers 180 GB either way: the
/// split is simply not available that way, and a plausible-looking wrong number
/// is worse than none. Every remaining honest route is a full walk of the disk
/// or a permission prompt for folders this app has no other reason to open,
/// and neither is worth it for a readout. macOS already has a screen that does
/// it properly, and — the part that matters — one you can act on, so the panel
/// offers a way there instead.
///
/// What IS free is the difference between the two free figures, and it is the
/// most useful thing here: on the machine this was written on, 29 GB of a
/// "full" disk turned out to be caches macOS would hand back on demand. That
/// gap is exactly why "the disk is full" and "there is nothing I can delete"
/// are so often both true, and naming it is most of the help.
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
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }

        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(values.volumeAvailableCapacity ?? 0)
        // Never claim more free than the disk holds, whatever the system says.
        let available = min(Int64(important), Int64(total))

        return DiskUsage(
            name: values.volumeName ?? "Startup disk",
            totalBytes: Int64(total),
            availableBytes: available,
            // The plain figure can exceed the purgeable-inclusive one on a
            // volume with nothing to purge, and a negative reclaimable figure
            // would be nonsense rather than merely odd.
            plainAvailableBytes: min(plain, available)
        )
    }
}
