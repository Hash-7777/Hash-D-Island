import Darwin
import Foundation

/// How much of the Mac's memory is in use.
///
/// On Apple Silicon there is one pool: the processor and the graphics share the
/// same physical memory, so this is the whole machine's memory rather than a
/// figure for one part of it.
public struct MemorySnapshot: Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    /// 0...1. Zero when the machine reports no memory at all, rather than a
    /// division by nothing.
    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

/// Reads memory use from the kernel's own counters. Public API, no permission,
/// no subprocess — the same class of reading as the processor load.
package enum MemoryReader {
    /// What "in use" means, in the terms the kernel reports.
    ///
    /// This is the figure Activity Monitor calls Memory Used, and matching it
    /// matters more than any other definition being defensible: a readout that
    /// disagrees with the tool people already check is a readout they will
    /// distrust, whichever of the two is more principled.
    ///
    /// App memory is the internal pages minus the ones the system is free to
    /// throw away; wired pages cannot be paged out at all; compressed pages are
    /// still occupying memory, just less of it than they were. Everything else
    /// the kernel counts — free, and the file cache — is memory available to
    /// whatever asks next, and counting it as used is what makes some readouts
    /// claim a Mac is permanently full.
    ///
    /// Pure and package-visible so the arithmetic is pinned by the checks
    /// rather than trusted.
    package static func usedBytes(
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        pageSize: UInt64
    ) -> UInt64 {
        // Purgeable can never exceed internal, but the two are sampled from one
        // struct that is not written atomically, so a subtraction that wraps is
        // possible rather than merely theoretical.
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return (app + wiredPages + compressedPages) * pageSize
    }

    /// How much memory the machine has, from `hw.memsize`.
    package static func totalBytes() -> UInt64 {
        var size: UInt64 = 0
        var length = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &size, &length, nil, 0) == 0 else { return 0 }
        return size
    }

    package static func read() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let total = totalBytes()
        guard total > 0 else { return nil }

        let used = usedBytes(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            pageSize: UInt64(vm_kernel_page_size)
        )
        // Never claim more in use than the machine holds, whatever the counters
        // say between samples.
        return MemorySnapshot(usedBytes: min(used, total), totalBytes: total)
    }
}
