import Foundation
import Darwin
import HashDIslandKit

/// Reads live upload/download throughput by diffing the kernel's per-interface
/// byte counters (getifaddrs / if_data) once a second. Public API only.
@MainActor
public final class NetworkMonitor: ObservableObject {
    @Published public private(set) var uploadBytesPerSec: Double = 0
    @Published public private(set) var downloadBytesPerSec: Double = 0

    private var sampler: PollingSampler?
    private var lastRx: UInt64 = 0
    private var lastTx: UInt64 = 0
    private var lastTime: TimeInterval = 0

    public init() {}

    public func start() {
        let counters = Self.counters()
        lastRx = counters.rx
        lastTx = counters.tx
        lastTime = Date().timeIntervalSinceReferenceDate
        sampler = PollingSampler(interval: 1.0) { [weak self] in self?.sample() }
        sampler?.start()
    }

    public func stop() {
        sampler?.stop()
        sampler = nil
    }

    private func sample() {
        let now = Date().timeIntervalSinceReferenceDate
        let dt = max(0.001, now - lastTime)
        let counters = Self.counters()

        // Counters can wrap (32-bit) or reset; treat a decrease as zero delta.
        let dRx = counters.rx >= lastRx ? counters.rx - lastRx : 0
        let dTx = counters.tx >= lastTx ? counters.tx - lastTx : 0

        let newDownload = Double(dRx) / dt
        let newUpload = Double(dTx) / dt

        // Only publish when the displayed MB/s value actually changes, so an idle
        // link (0.00) triggers no SwiftUI redraws at all.
        if Formatters.megabytesPerSecond(newDownload) != Formatters.megabytesPerSecond(downloadBytesPerSec) {
            downloadBytesPerSec = newDownload
        }
        if Formatters.megabytesPerSecond(newUpload) != Formatters.megabytesPerSecond(uploadBytesPerSec) {
            uploadBytesPerSec = newUpload
        }

        lastRx = counters.rx
        lastTx = counters.tx
        lastTime = now
    }

    /// Sum of received/sent bytes across all non-loopback link-layer interfaces.
    private static func counters() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0
        var tx: UInt64 = 0

        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let interface = pointer.pointee
            if let sockaddr = interface.ifa_addr,
               sockaddr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: interface.ifa_name)
                if !name.hasPrefix("lo"), let data = interface.ifa_data {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(stats.ifi_ibytes)
                    tx += UInt64(stats.ifi_obytes)
                }
            }
            cursor = interface.ifa_next
        }
        return (rx, tx)
    }
}
