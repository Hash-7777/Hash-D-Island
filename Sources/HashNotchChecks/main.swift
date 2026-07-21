import Foundation
import SwiftUI
import CoreGraphics
import HashNotchKit
import FeatureMedia
import FeatureActivities
import FeatureTokens

/// Writes `content` to a fresh temp file and returns its URL.
func tempFile(_ content: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashnotch-check-\(UUID().uuidString).json")
    try? content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

// A tiny, dependency-free check runner. Prints one line per check and exits
// non-zero if any fails, so it works as a pre-push gate under the Command Line
// Tools alone (no XCTest / Swift Testing needed).

var failures = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        print("  ok   \(name)")
    } else {
        print("  FAIL \(name)")
        failures += 1
    }
}

/// A throwaway feature — proves the core is decoupled from concrete features.
@MainActor
private final class StubFeature: NotchFeature {
    let id: String
    let title: String
    let placement: FeaturePlacement
    init(id: String, placement: FeaturePlacement) {
        self.id = id
        self.title = id
        self.placement = placement
    }
    func makeView(context: FeatureContext) -> AnyView { AnyView(EmptyView()) }
}

MainActor.assumeIsolated {
    print("HashNotch core checks")

    // Registry keeps registration order.
    let ordered = FeatureRegistry()
    ordered.register([
        StubFeature(id: "a", placement: .leading),
        StubFeature(id: "b", placement: .trailing),
        StubFeature(id: "c", placement: .leading),
    ])
    check("registry keeps order", ordered.features.map(\.id) == ["a", "b", "c"])

    // Registry filters by placement.
    check("filter leading", ordered.features(for: .leading).map(\.id) == ["a", "c"])
    check("filter trailing", ordered.features(for: .trailing).map(\.id) == ["b"])
    check("filter expanded empty", ordered.features(for: .expanded).isEmpty)

    // Island sizing: collapsed matches the notch, expanded is larger.
    let state = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 656, y: 950, width: 200, height: 32),
        hasNotch: true
    ))
    check("notch width", state.notchWidth == 200)
    check("collapsed matches notch", state.collapsedWidth == 200)
    check("expanded is larger", state.expandedWidth > state.collapsedWidth && state.expandedHeight > state.collapsedHeight)

    // Rate formatter scales units.
    check("rate B", Formatters.rate(512).unit == "B/s")
    check("rate KB", Formatters.rate(9_216).value == "9" && Formatters.rate(9_216).unit == "KB/s")
    check("rate MB", Formatters.rate(5_242_880).unit == "MB/s")

    // Network readout is always MB/s with two decimals (fixed layout).
    check("mbps unit fixed", Formatters.megabytesUnit == "MB/s")
    check("mbps small", Formatters.megabytesPerSecond(12_288) == "0.01")
    check("mbps whole", Formatters.megabytesPerSecond(5_242_880) == "5.00")

    // Compact token counts.
    check("count small", Formatters.compactCount(812) == "812")
    check("count K", Formatters.compactCount(12_300) == "12.3K")
    check("count M", Formatters.compactCount(4_500_000) == "4.5M")
    check("count B", Formatters.compactCount(1_280_000_000) == "1.28B")

    // Artwork downloads: HTTPS to Spotify's own CDN only — the app's single
    // network access must never fetch an arbitrary or non-HTTPS URL.
    check("artwork allows Spotify CDN", ArtworkPolicy.isTrustedURL("https://i.scdn.co/image/abc123"))
    check("artwork allows Spotify CDN alt", ArtworkPolicy.isTrustedURL("https://images.spotifycdn.com/x.jpg"))
    check("artwork allows YouTube thumbs", ArtworkPolicy.isTrustedURL("https://i.ytimg.com/vi/abc123/hqdefault.jpg"))
    check("artwork refuses ytimg lookalike", !ArtworkPolicy.isTrustedURL("https://evilytimg.com/vi/abc123/x.jpg"))
    check("artwork refuses http", !ArtworkPolicy.isTrustedURL("http://i.scdn.co/image/abc123"))
    check("artwork refuses other hosts", !ArtworkPolicy.isTrustedURL("https://example.com/a.jpg"))
    check("artwork refuses lookalike host", !ArtworkPolicy.isTrustedURL("https://evilscdn.co/a.jpg"))
    check("artwork refuses file scheme", !ArtworkPolicy.isTrustedURL("file:///etc/passwd"))
    check("artwork refuses garbage", !ArtworkPolicy.isTrustedURL("not a url"))

    // Activities feed: other processes write it, so every field is bounded
    // before it reaches the UI.
    let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
    let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))

    let feed = tempFile("""
    [
      {"id": "a", "title": "First", "progress": 2.5},
      {"id": "a", "title": "Duplicate of first"},
      {"id": "b", "title": "Second", "progress": -1, "endsAt": "\(future)"},
      {"id": "", "title": "No id"},
      {"id": "c", "title": ""},
      {"id": "d", "title": "Expired", "endsAt": "\(past)"}
    ]
    """)
    let parsed = ActivitiesReader.read(from: feed)
    check("feed keeps first of duplicate ids", parsed.map(\.id) == ["a", "b"])
    check("feed keeps titles", parsed.first?.title == "First")
    check("feed clamps progress high", parsed.first?.progress == 1)
    check("feed clamps progress low", parsed.last?.progress == 0)
    check("feed drops expired", !parsed.contains { $0.id == "d" })
    try? FileManager.default.removeItem(at: feed)

    let overflowing = (0..<20).map { "{\"id\": \"x\($0)\", \"title\": \"Item \($0)\"}" }
    let bigFeed = tempFile("[\(overflowing.joined(separator: ","))]")
    check("feed caps activity count", ActivitiesReader.read(from: bigFeed).count == ActivitiesReader.maxActivities)
    try? FileManager.default.removeItem(at: bigFeed)

    let hugeFeed = tempFile("[{\"id\": \"a\", \"title\": \"\(String(repeating: "x", count: ActivitiesReader.maxFeedBytes))\"}]")
    check("feed refuses oversized file", ActivitiesReader.read(from: hugeFeed).isEmpty)
    try? FileManager.default.removeItem(at: hugeFeed)

    let badFeed = tempFile("this is not json")
    check("feed tolerates invalid JSON", ActivitiesReader.read(from: badFeed).isEmpty)
    try? FileManager.default.removeItem(at: badFeed)

    let fractional = tempFile("[{\"id\": \"f\", \"title\": \"Fractional\", \"endsAt\": \"2099-01-01T12:00:00.500Z\"}]")
    check("feed parses fractional endsAt", ActivitiesReader.read(from: fractional).first?.endsAt != nil)
    try? FileManager.default.removeItem(at: fractional)

    // Token files: counts only today's assistant lines, each message id once,
    // ignores malformed ones, and keeps cache tokens out of the headline.
    let startOfToday = Calendar.current.startOfDay(for: Date())
    let todayStamp = ISO8601DateFormatter().string(from: Date())
    let oldStamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-172_800))

    let claudeFile = tempFile("""
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}
    {"type":"assistant","timestamp":"\(oldStamp)","message":{"id":"m2","usage":{"input_tokens":999,"output_tokens":999}}}
    not json at all
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"usage":{"input_tokens":1,"output_tokens":2}}}
    {"type":"user","timestamp":"\(todayStamp)","message":{"id":"m9","usage":{"input_tokens":500,"output_tokens":500}}}
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"m3","usage":{"input_tokens":10,"output_tokens":20}}}
    """)
    var seenIDs = Set<String>()
    let claudeCounted = TokenUsageReader.tokens(inClaudeFile: claudeFile, since: startOfToday, seen: &seenIDs)
    check("claude counts today's io once per message", claudeCounted.io == 183)
    check("claude separates cache", claudeCounted.cache == 1200)
    check("claude ignores non-assistant lines", seenIDs == ["m1", "m3"])

    // The same message id appearing in ANOTHER file (continued session) must
    // also be skipped — the seen-set spans the whole scan.
    let continuedFile = tempFile("""
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":50}}}
    """)
    check("claude dedups across files", TokenUsageReader.tokens(inClaudeFile: continuedFile, since: startOfToday, seen: &seenIDs).io == 0)
    try? FileManager.default.removeItem(at: claudeFile)
    try? FileManager.default.removeItem(at: continuedFile)

    let ecosystemFile = tempFile("""
    {"ts":"\(todayStamp)","input_tokens":10,"output_tokens":5,"cache_read":100,"cache_write":20}
    {"ts":"\(oldStamp)","input_tokens":7,"output_tokens":7}
    """)
    let ecosystemCounted = TokenUsageReader.tokens(inEcosystemFile: ecosystemFile, since: startOfToday)
    check("ecosystem counts today's io", ecosystemCounted.io == 15)
    check("ecosystem separates cache", ecosystemCounted.cache == 120)
    try? FileManager.default.removeItem(at: ecosystemFile)

    // A file larger than one read chunk (1 MB) exercises the streaming path's
    // carry-over of partial lines across chunk boundaries.
    let padding = String(repeating: "x", count: 400)
    let bigLines = (0..<4000).map {
        "{\"type\":\"assistant\",\"timestamp\":\"\(todayStamp)\",\"pad\":\"\(padding)\",\"message\":{\"id\":\"big-\($0)\",\"usage\":{\"input_tokens\":1,\"output_tokens\":0}}}"
    }
    let bigFile = tempFile(bigLines.joined(separator: "\n"))
    var bigSeen = Set<String>()
    check("streaming counts across chunk boundaries", TokenUsageReader.tokens(inClaudeFile: bigFile, since: startOfToday, seen: &bigSeen).io == 4000)
    try? FileManager.default.removeItem(at: bigFile)

    // Settings: defaults, updates, and persistence round-trip.
    let suite = "hashnotch.checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = SettingsStore(defaults: defaults)
    let stub = StubFeature(id: "x", placement: .leading)
    store.seed(features: [stub])
    check("settings seed enables", store.isEnabled("x"))
    check("settings seed placement", store.features["x"]?.placement == .leading)

    store.update("x") { $0.enabled = false; $0.styleID = "word" }
    check("settings update disables", store.isEnabled("x") == false)
    check("settings update style", store.style(for: "x") == "word")

    store.flush()
    let reloaded = SettingsStore(defaults: defaults)
    check("settings persist enabled", reloaded.isEnabled("x") == false)
    check("settings persist style", reloaded.style(for: "x") == "word")
    defaults.removePersistentDomain(forName: suite)
}

if failures == 0 {
    print("All checks passed.")
    exit(0)
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
