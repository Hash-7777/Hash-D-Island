import Foundation

/// How full the startup disk is.
public struct DiskUsage: Equatable {
    /// The volume's name, as Finder shows it.
    public let name: String
    public let totalBytes: Int64
    public let availableBytes: Int64

    public init(name: String, totalBytes: Int64, availableBytes: Int64) {
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    /// Whole percent used, 0 to 100. Zero when the volume reports no size,
    /// rather than a division by nothing.
    public var percentUsed: Int {
        guard totalBytes > 0 else { return 0 }
        return Int((Double(usedBytes) / Double(totalBytes) * 100).rounded())
    }
}

/// Reads the startup disk's capacity from the public file-system API.
///
/// `volumeAvailableCapacityForImportantUsage` rather than the plain available
/// figure, because that is the number macOS itself shows you: it counts space
/// currently held by things the system is willing to purge — caches, local
/// snapshots — as available, which is why Finder's number and `df` disagree by
/// tens of gigabytes and Finder's is the one people recognise.
///
/// No permission of any kind is involved. It asks how big the disk is, not what
/// is on it, and it never enumerates a single file.
package enum StorageReader {
    package static let volumeURL = URL(fileURLWithPath: "/")

    static func read() -> DiskUsage? {
        read(volume: volumeURL)
    }

    package static func read(volume: URL) -> DiskUsage? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }

        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return DiskUsage(
            name: values.volumeName ?? "Startup disk",
            totalBytes: Int64(total),
            // Never claim more free than the disk holds, whatever the system says.
            availableBytes: min(Int64(available), Int64(total))
        )
    }
}
