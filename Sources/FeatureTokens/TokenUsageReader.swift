import Foundation

/// Today's token totals, per source. `claude` / `hashCortx` / `hashCerebrum`
/// count input + output tokens (the headline number, matching HashMeterAi).
/// `cached` is the much larger cache read/write total, kept separate so it never
/// inflates the headline.
public struct TokenTotals: Equatable {
    public var claude: Int64 = 0
    public var hashCortx: Int64 = 0
    public var hashCerebrum: Int64 = 0
    public var cached: Int64 = 0

    public var total: Int64 { claude + hashCortx + hashCerebrum }
}

/// Reads real token usage from the local files the AI tools write — the same
/// sources HashMeterAi uses:
///
///   • Claude Code   ~/.claude/projects/**/*.jsonl  (message.usage per line)
///   • HashCortx     ~/.hashcortx/usage.jsonl       (ecosystem contract)
///   • HashCerebrum  app-data usage.jsonl           (ecosystem contract)
///
/// Only files touched today are opened, and files are streamed line by line in
/// 1 MB chunks — a session transcript can grow to hundreds of megabytes, and
/// loading it whole every poll would be a real memory and energy cost. Call
/// from a background queue — it does file IO and JSON parsing.
package enum TokenUsageReader {
    static func readToday() -> TokenTotals {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        var totals = TokenTotals()

        let claude = claudeTokens(since: startOfToday)
        totals.claude = claude.io
        totals.cached += claude.cache

        let cortx = tokens(inEcosystemFile: hashCortxURL, since: startOfToday)
        totals.hashCortx = cortx.io
        totals.cached += cortx.cache

        let cerebrum = tokens(inEcosystemFile: hashCerebrumURL, since: startOfToday)
        totals.hashCerebrum = cerebrum.io
        totals.cached += cerebrum.cache

        return totals
    }

    // MARK: Sources

    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private static var hashCortxURL: URL {
        home.appendingPathComponent(".hashcortx/usage.jsonl")
    }

    private static var hashCerebrumURL: URL {
        home.appendingPathComponent("Library/Application Support/com.hashcerebrum.desktop/usage.jsonl")
    }

    // MARK: Claude Code

    private static func claudeTokens(since: Date) -> (io: Int64, cache: Int64) {
        let projects = home.appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projects,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var io: Int64 = 0
        var cache: Int64 = 0
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < since { continue }
            let file = tokens(inClaudeFile: url, since: since)
            io += file.io
            cache += file.cache
        }
        return (io, cache)
    }

    package static func tokens(inClaudeFile url: URL, since: Date) -> (io: Int64, cache: Int64) {
        var io: Int64 = 0
        var cache: Int64 = 0
        forEachLine(of: url) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  isToday(object["timestamp"] as? String, since: since),
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }
            io += int(usage["input_tokens"]) + int(usage["output_tokens"])
            cache += int(usage["cache_read_input_tokens"]) + int(usage["cache_creation_input_tokens"])
        }
        return (io, cache)
    }

    // MARK: Ecosystem usage.jsonl

    package static func tokens(inEcosystemFile url: URL, since: Date) -> (io: Int64, cache: Int64) {
        var io: Int64 = 0
        var cache: Int64 = 0
        forEachLine(of: url) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  isToday(object["ts"] as? String, since: since) else { return }
            io += int(object["input_tokens"]) + int(object["output_tokens"])
            cache += int(object["cache_read"]) + int(object["cache_write"])
        }
        return (io, cache)
    }

    // MARK: Line streaming

    /// Calls `body` with each newline-terminated line of the file as raw bytes,
    /// reading in 1 MB chunks so even a huge transcript never sits in memory
    /// whole. A partial line at a chunk boundary is carried into the next read.
    private static func forEachLine(of url: URL, _ body: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var carry = Data()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            var data: Data
            if carry.isEmpty {
                data = chunk
            } else {
                data = carry
                data.append(chunk)
                carry = Data()
            }

            var start = data.startIndex
            while let newline = data[start...].firstIndex(of: 0x0A) {
                if newline > start {
                    body(data.subdata(in: start..<newline))
                }
                start = data.index(after: newline)
            }
            if start < data.endIndex {
                carry = Data(data[start...])
            }
        }
        if !carry.isEmpty {
            body(carry)
        }
    }

    // MARK: Helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction = ISO8601DateFormatter()

    private static func isToday(_ timestamp: String?, since: Date) -> Bool {
        guard let timestamp else { return false }
        let date = isoFormatter.date(from: timestamp)
            ?? isoFormatterNoFraction.date(from: timestamp)
        guard let date else { return false }
        return date >= since
    }

    private static func int(_ value: Any?) -> Int64 {
        if let number = value as? Int64 { return number }
        if let number = value as? Int { return Int64(number) }
        if let number = value as? Double { return Int64(number) }
        return 0
    }
}
