import Foundation
import SwiftUI
import CoreGraphics
import HashDIslandKit
import FeatureMedia
import FeatureActivities
import FeatureTokens
import FeatureBattery
import FeatureDownloads
import FeatureAirPods
import FeatureNetwork

/// Writes `content` to a fresh temp file and returns its URL.
func tempFile(_ content: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashdisland-check-\(UUID().uuidString).json")
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

/// A stub that remembers whether it is running, so the checks can tell apart a
/// feature that is hidden from one that has actually been stopped.
@MainActor
private final class CountingFeature: NotchFeature {
    let id: String
    let title: String
    let placement: FeaturePlacement = .expanded
    private(set) var isRunning = false
    private(set) var starts = 0

    init(id: String) {
        self.id = id
        self.title = id
    }

    func start(context: FeatureContext) {
        isRunning = true
        starts += 1
    }
    func stop() { isRunning = false }
    func makeView(context: FeatureContext) -> AnyView { AnyView(EmptyView()) }
}

MainActor.assumeIsolated {
    print("Hash D Island core checks")

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

    // Switching a feature off stops it, rather than merely hiding it. This is a
    // privacy promise as much as a battery one: a feature that is off must not
    // still be listing your Downloads folder or asking your browser what it is
    // playing.
    let runSuite = "hashdisland.checks.running.\(UUID().uuidString)"
    let runDefaults = UserDefaults(suiteName: runSuite)!
    let runSettings = SettingsStore(defaults: runDefaults)
    let onFeature = CountingFeature(id: "on")
    let offFeature = CountingFeature(id: "off")
    let runRegistry = FeatureRegistry()
    runRegistry.register([onFeature, offFeature])
    runSettings.seed(features: runRegistry.features)
    runSettings.update("off") { $0.enabled = false }

    let runContext = FeatureContext(settings: runSettings)
    runRegistry.syncRunning(context: runContext)
    check("a feature that is on is started", onFeature.isRunning)
    check("a feature that is off is never started", offFeature.isRunning == false)
    check("only the running feature is tracked", runRegistry.runningIDs == ["on"])

    // Flipping a switch takes effect on the feature itself, both ways.
    runSettings.update("off") { $0.enabled = true }
    runRegistry.syncRunning(context: runContext)
    check("switching a feature on starts it", offFeature.isRunning)

    runSettings.update("on") { $0.enabled = false }
    runRegistry.syncRunning(context: runContext)
    check("switching a feature off stops it", onFeature.isRunning == false)
    check("the other feature is left alone", offFeature.isRunning)

    // Settings publish on every change, including reorders and style changes,
    // so the sync must be free to run often without restarting anything.
    let startsBefore = offFeature.starts
    runRegistry.syncRunning(context: runContext)
    runRegistry.syncRunning(context: runContext)
    check("syncing again does not restart a running feature", offFeature.starts == startsBefore)

    runRegistry.stopAll()
    check("stopping everything clears what is running", runRegistry.runningIDs.isEmpty)
    UserDefaults.standard.removePersistentDomain(forName: runSuite)

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

    // Battery time-remaining reads as explicit hours/minutes, never a clock.
    check("hm minutes only", Formatters.hoursMinutes(45) == "45m")
    check("hm hours and minutes", Formatters.hoursMinutes(154) == "2h 34m")
    check("hm whole hours", Formatters.hoursMinutes(180) == "3h")
    check("hm under an hour zero-safe", Formatters.hoursMinutes(0) == "0m")

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

    // Playback commands. Play and pause are separate on purpose: a toggle sent
    // to a player that has released the now-playing session is accepted,
    // reported as successful, and ignored — which is exactly how a paused track
    // used to refuse to resume. Pinning the mapping here means the two can
    // never be swapped silently.
    check("play scripts as play", MediaCommand.play.scriptVerb == "play")
    check("pause scripts as pause", MediaCommand.pause.scriptVerb == "pause")
    check("next scripts as next track", MediaCommand.next.scriptVerb == "next track")
    check(
        "previous scripts as previous track",
        MediaCommand.previous.scriptVerb == "previous track"
    )
    check("play is remote code 0", MediaCommand.play.remoteCode == 0)
    check("pause is remote code 1", MediaCommand.pause.remoteCode == 1)
    check("next is remote code 4", MediaCommand.next.remoteCode == 4)
    check("previous is remote code 5", MediaCommand.previous.remoteCode == 5)
    check(
        "no command is ever a toggle",
        ![MediaCommand.play, .pause, .next, .previous]
            .contains { $0.remoteCode == 2 }
    )

    // A player takes a beat to obey a command. Inside that beat the button
    // keeps what it showed; outside it the player is always right.
    func settles(_ since: TimeInterval, _ polled: Bool, _ optimistic: Bool) -> Bool {
        MediaMonitor.keepsOptimisticPlayState(
            secondsSinceCommand: since,
            window: 1.5,
            polledIsPlaying: polled,
            optimisticIsPlaying: optimistic
        )
    }
    check("a stale poll right after pressing play is ignored", settles(0.2, false, true))
    check("a stale poll right after pressing pause is ignored", settles(0.2, true, false))
    check("an agreeing poll is never overridden", settles(0.2, true, true) == false)
    check("the player wins once the window has passed", settles(2.0, false, true) == false)
    check("the window is exclusive at its edge", settles(1.5, false, true) == false)

    // Panel-only readouts sample only while anyone can see them.
    let visibility = PanelVisibility()
    var samples = 0
    let visible = VisibleSampler(interval: 60, visibility: visibility) { samples += 1 }
    visible.start()
    check("a shut panel samples nothing", samples == 0)
    visibility.setOpen(true)
    check("opening the panel samples at once", samples == 1)
    visibility.setOpen(true)
    check("staying open does not resample", samples == 1)
    visibility.setOpen(false)
    visibility.setOpen(true)
    check("reopening samples again", samples == 2)
    visible.stop()
    visibility.setOpen(false)
    visibility.setOpen(true)
    check("a stopped sampler ignores the panel", samples == 2)

    // Watching a folder replaces re-listing it on a timer, so it has to
    // actually fire — a silent failure here would mean a finished download is
    // never announced again.
    let watchDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashdisland-watch-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)
    var changes = 0
    let watcher = DirectoryWatcher(url: watchDir, coalesce: 0.05) { changes += 1 }
    check("a folder that exists can be watched", watcher != nil)

    try? "x".write(to: watchDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    check("writing into the folder reports a change", changes >= 1)

    let afterFirst = changes
    try? "y".write(to: watchDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    check("the watch keeps working after the first change", changes > afterFirst)

    watcher?.stop()
    let afterStop = changes
    try? "z".write(to: watchDir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    check("a stopped watch reports nothing", changes == afterStop)

    check(
        "a folder that does not exist is not watched",
        DirectoryWatcher(url: watchDir.appendingPathComponent("nope"), onChange: {}) == nil
    )
    try? FileManager.default.removeItem(at: watchDir)

    // Throughput is a difference over time, so a reading taken after the panel
    // was shut (or the Mac asleep) is too old to diff against and is used as a
    // fresh baseline instead of being reported as the current speed.
    check("a fresh reading is usable", NetworkMonitor.isStaleBaseline(dt: 1.0, interval: 1.0) == false)
    check("a slightly late reading is usable", NetworkMonitor.isStaleBaseline(dt: 2.5, interval: 1.0) == false)
    check("a reading from minutes ago is not", NetworkMonitor.isStaleBaseline(dt: 600, interval: 1.0))

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

    // A logo path comes from the same untrusted feed as everything else, so it
    // is only honoured when it names a readable image that really exists.
    let logoDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hashdisland-logo-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: logoDir, withIntermediateDirectories: true)
    let realLogo = logoDir.appendingPathComponent("brand.png")
    // A one-pixel PNG is enough: the reader checks the file, not the pixels.
    let onePixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    try? onePixelPNG.write(to: realLogo)
    let notAnImage = logoDir.appendingPathComponent("notes.txt")
    try? "hello".write(to: notAnImage, atomically: true, encoding: .utf8)

    func imagePath(forFeed value: String) -> String? {
        let file = tempFile("[{\"id\":\"L\",\"title\":\"Logo\",\"image\":\"\(value)\"}]")
        defer { try? FileManager.default.removeItem(at: file) }
        return ActivitiesReader.read(from: file).first?.imagePath
    }

    check("a real image is accepted", imagePath(forFeed: realLogo.path) == realLogo.path)
    check("a missing file is refused", imagePath(forFeed: logoDir.appendingPathComponent("gone.png").path) == nil)
    check("a non-image file is refused", imagePath(forFeed: notAnImage.path) == nil)
    check("a folder is refused", imagePath(forFeed: logoDir.path) == nil)
    check("an empty path is refused", imagePath(forFeed: "") == nil)
    check(
        "a path that climbs out is resolved before it is judged",
        imagePath(forFeed: logoDir.appendingPathComponent("../../etc/passwd").path) == nil
    )

    // Size is part of the same judgement: the logo is decoded on the main
    // thread, so an oversized one is refused before it can ever reach it.
    let hugeLogo = logoDir.appendingPathComponent("huge.png")
    var oversized = onePixelPNG
    oversized.append(Data(count: ActivitiesReader.maxImageBytes))
    try? oversized.write(to: hugeLogo)
    check("an oversized image is refused", imagePath(forFeed: hugeLogo.path) == nil)

    let emptyLogo = logoDir.appendingPathComponent("empty.png")
    try? Data().write(to: emptyLogo)
    check("an empty image is refused", imagePath(forFeed: emptyLogo.path) == nil)
    check(
        "an activity with no image still has its symbol",
        ActivitiesReader.read(from: tempFile("[{\"id\":\"S\",\"title\":\"Sym\",\"icon\":\"bolt.fill\"}]"))
            .first.map { $0.imagePath == nil && $0.icon == "bolt.fill" } == true
    )
    try? FileManager.default.removeItem(at: logoDir)

    // A notice announces something that already happened, so it draws no
    // countdown and leaves on its own. A countdown still counts.
    let notices = tempFile("""
    [
      {"id": "n1", "title": "Claude finished", "dismissAfter": 3, "endsAt": "\(future)"},
      {"id": "n2", "title": "Food delivery", "endsAt": "\(future)"},
      {"id": "n3", "title": "Clamped low", "dismissAfter": 0.1, "endsAt": "\(future)"},
      {"id": "n4", "title": "Clamped high", "dismissAfter": 9000, "endsAt": "\(future)"}
    ]
    """)
    let noticed = ActivitiesReader.read(from: notices)
    func activity(_ id: String) -> LiveActivity? { noticed.first { $0.id == id } }
    check("a notice draws no countdown", activity("n1")?.showsCountdown == false)
    check("a notice reports no time left", activity("n1")?.secondsLeft(now: Date()) == nil)
    check("a countdown still counts down", activity("n2")?.showsCountdown == true)
    check("a countdown still reports time left", (activity("n2")?.secondsLeft(now: Date()) ?? 0) > 0)
    check("a too-short notice is clamped up", activity("n3")?.dismissAfter == 1)
    check("a too-long notice is clamped down", activity("n4")?.dismissAfter == 30)

    // The dismissal moment is measured from when the notice first appeared.
    let seen = Date()
    check(
        "a notice leaves after its own delay",
        activity("n1")?.dismissalDate(firstSeen: seen) == seen.addingTimeInterval(3)
    )
    check("a countdown never self-dismisses", activity("n2")?.dismissalDate(firstSeen: seen) == nil)
    try? FileManager.default.removeItem(at: notices)

    // The icon is a string from the same untrusted feed, so it is bounded like
    // every other field — and an absent or empty one still draws something.
    let icons = tempFile("""
    [
      {"id": "i1", "title": "Long icon", "icon": "\(String(repeating: "x", count: 500))"},
      {"id": "i2", "title": "Empty icon", "icon": ""},
      {"id": "i3", "title": "No icon"}
    ]
    """)
    let iconParsed = ActivitiesReader.read(from: icons)
    check("feed caps icon length", (iconParsed.first { $0.id == "i1" }?.icon.count ?? 999) <= 64)
    check("feed defaults empty icon", (iconParsed.first { $0.id == "i2" })?.icon == "app.badge")
    check("feed defaults missing icon", (iconParsed.first { $0.id == "i3" })?.icon == "app.badge")
    try? FileManager.default.removeItem(at: icons)

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
    // Processed tokens (input + cache-write + output), each message once:
    // m1 = 100+200+50, the no-id line = 1+2, m3 = 10+20.
    check("claude counts processed tokens once per message", claudeCounted.io == 383)
    check("claude separates cache reads", claudeCounted.cache == 1000)
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
    // Processed = 10+5+20 (cache_write counts, cache_read does not).
    check("ecosystem counts processed tokens", ecosystemCounted.io == 35)
    check("ecosystem separates cache reads", ecosystemCounted.cache == 100)
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

    // A line with no newline in sight is a corrupt file, not a usage record: it
    // is dropped rather than buffered without limit, and the valid lines around
    // it still count.
    let monsterLine = "{\"pad\":\"\(String(repeating: "x", count: 9 << 20))\"}"
    let monsterFile = tempFile("""
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"before","usage":{"input_tokens":7,"output_tokens":0}}}
    \(monsterLine)
    {"type":"assistant","timestamp":"\(todayStamp)","message":{"id":"after","usage":{"input_tokens":3,"output_tokens":0}}}
    """)
    var monsterSeen = Set<String>()
    let monsterCounted = TokenUsageReader.tokens(inClaudeFile: monsterFile, since: startOfToday, seen: &monsterSeen)
    check("streaming drops an unbounded line", monsterCounted.io == 10)
    check("streaming resumes after a dropped line", monsterSeen == ["before", "after"])
    try? FileManager.default.removeItem(at: monsterFile)

    // Low-battery announcements fire exactly when a threshold is crossed
    // downward, never on charge or within a band.
    check("low fires crossing 20", BatteryMonitor.crossedLowThreshold(from: 21, to: 20) == 20)
    check("low fires crossing 10", BatteryMonitor.crossedLowThreshold(from: 15, to: 9) == 10)
    check("low silent inside band", BatteryMonitor.crossedLowThreshold(from: 19, to: 15) == nil)
    check("low silent when rising", BatteryMonitor.crossedLowThreshold(from: 9, to: 30) == nil)

    // Being on power and being charged by it are different facts. The state a
    // Mac is hardest to catch in — plugged in, parked at 80% by optimised
    // charging, deliberately not charging — is the one that must not claim to
    // be charging, so every combination is pinned here rather than waited for.
    check(
        "unplugged is discharging",
        BatteryMonitor.state(onPower: false, isCharging: false, percentage: 64) == .discharging
    )
    check(
        "plugged in and filling is charging",
        BatteryMonitor.state(onPower: true, isCharging: true, percentage: 64) == .charging
    )
    check(
        "plugged in and full is charged",
        BatteryMonitor.state(onPower: true, isCharging: false, percentage: 100) == .charged
    )
    check(
        "plugged in and parked at 80 is on hold, not charging",
        BatteryMonitor.state(onPower: true, isCharging: false, percentage: 80) == .onHold
    )
    check(
        "a full battery still reads charged just under 100",
        BatteryMonitor.state(onPower: true, isCharging: false, percentage: 96) == .charged
    )
    check(
        "power state alone never implies charging",
        BatteryMonitor.state(onPower: true, isCharging: false, percentage: 50) != .charging
    )

    // Only the low-battery warning earns the longer stay on the notch.
    check("a low warning is a warning", BatteryEvent.lowBattery(10).isWarning)
    check("charging is not a warning", BatteryEvent.startedCharging(50).isWarning == false)
    check("fully charged is not a warning", BatteryEvent.fullyCharged(100).isWarning == false)
    check("unplugging is not a warning", BatteryEvent.unplugged(80).isWarning == false)

    // Downloads: browser part-files are recognized, finished files are not.
    check("part crdownload", DownloadsMonitor.isPartFileName("movie.mp4.crdownload"))
    check("part download", DownloadsMonitor.isPartFileName("photo.jpg.download"))
    check("part part", DownloadsMonitor.isPartFileName("archive.zip.part"))
    check("finished not part", !DownloadsMonitor.isPartFileName("movie.mp4"))
    check("finished pdf not part", !DownloadsMonitor.isPartFileName("report.pdf"))

    // AirPods: parse battery out of `system_profiler SPBluetoothDataType`, only
    // for the AirPods block, only while connected (levels present).
    let apConnected = [
        "    Bluetooth:",
        "        Connected:",
        "          Hash's AirPods:",
        "              Case Battery Level: 81%",
        "              Left Battery Level: 81%",
        "              Right Battery Level: 100%",
        "              Minor Type: Headphones",
        "          Hash's Speaker:",
        "              Battery Level: 55%",
    ].joined(separator: "\n")
    let ap = AirPodsReader.parse(apConnected)
    check("airpods parses left", ap.left == 81)
    check("airpods parses right", ap.right == 100)
    check("airpods parses case", ap.caseLevel == 81)
    check("airpods stops at next device", ap.single == nil)
    check("airpods glance is the lower earbud", ap.glance == 81)

    let apDisconnected = [
        "        Not Connected:",
        "          Hash's AirPods:",
        "              Address: 08:65:18:5F:AF:0C",
        "              Minor Type: Headphones",
    ].joined(separator: "\n")
    check("airpods empty when disconnected", AirPodsReader.parse(apDisconnected).isEmpty)

    let apSingle = [
        "          Someone's AirPods Max:",
        "              Battery Level: 90%",
        "              Minor Type: Headphones",
    ].joined(separator: "\n")
    let single = AirPodsReader.parse(apSingle)
    check("airpods single-battery level", single.single == 90 && single.glance == 90)

    // System volume via CoreAudio: readable in range, and a same-value write
    // round-trips (harmless — it sets the volume it already has).
    if let volume = SystemVolume.read() {
        check("volume read in range", (0...100).contains(volume))
        SystemVolume.set(volume)
        check("volume same-value write round-trips", SystemVolume.read() == volume)
    } else {
        print("  note volume unavailable on this output device (skipped)")
    }

    // Settings: defaults, updates, and persistence round-trip.
    let suite = "hashdisland.checks.\(UUID().uuidString)"
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

    // The overlay window keeps ONE width for its whole life. A width that
    // changes has to move the left edge to stay centred, and that move is
    // instant while SwiftUI animates the content re-centring inside it — the two
    // do not cancel, and the island sweeps sideways. Measured on a real close
    // before this was fixed: the panel sat at 262 in a 524-wide window and 176
    // in a 352-wide one.
    let widthState = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832),
        notchRect: CGRect(x: 562, y: 804, width: 156, height: 28),
        hasNotch: true
    ))
    let notch = CGRect(x: 562, y: 804, width: 156, height: 28)
    let constant = NotchWindowController.constantWidth(for: notch, state: widthState)
    check("the window is wide enough for the resting notch", constant >= widthState.collapsedWidth)
    check("wide enough for the open panel", constant >= widthState.expandedWidth)
    check(
        "wide enough for the live strip's furthest reach",
        constant >= 2 * max(
            widthState.liveLeadingWidth + notch.width / 2,
            notch.width / 2 + widthState.liveTrailingWidth
        )
    )
    check("and it is a whole number of points", constant == constant.rounded())

    // The same must hold on every shape of display, including a notchless one
    // where the island is a small stand-in pill.
    var coversEveryState = true
    for width in [132.0, 156.0, 200.0, 240.0] {
        let rect = CGRect(x: 640 - width / 2, y: 804, width: width, height: 28)
        let s = NotchState(geometry: NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832),
            notchRect: rect,
            hasNotch: true
        ))
        let w = NotchWindowController.constantWidth(for: rect, state: s)
        let liveReach = 2 * max(s.liveLeadingWidth + width / 2, width / 2 + s.liveTrailingWidth)
        if w < s.collapsedWidth || w < s.expandedWidth || w < liveReach { coversEveryState = false }
    }
    check("one width covers every state on any notch size", coversEveryState)

    // A shape that grows out of the notch has to converge ON the notch. The
    // live strip is lopsided on purpose, so its own centre is the wrong point:
    // anchoring there would collapse it beside the hardware rather than into it.
    let stripState = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832),
        notchRect: CGRect(x: 562, y: 804, width: 156, height: 28),
        hasNotch: true
    ))
    let anchor = stripState.notchAnchorInLiveStrip
    // The notch's centre sits at leading + half the notch, within the whole
    // strip — here 56 + 78 of 382.
    let expectedAnchor = (56.0 + 78.0) / 382.0
    check("the strip anchors on the notch", abs(anchor - expectedAnchor) < 0.001)
    check("which is left of the strip's own centre", anchor < 0.5)
    check(
        "the anchor lands inside the notch",
        anchor * stripState.liveWidth > 56 && anchor * stripState.liveWidth < 56 + 156
    )
    check(
        "a drop starts exactly as wide as the notch",
        abs(stripState.notchWidth / stripState.expandedWidth - 156.0 / 300.0) < 0.001
    )

    // On a notched display the island hangs from the screen's top edge and
    // wears the notch exactly. On one without, it must NOT: painting black over
    // the menu bar reads as a fault, so it hangs below it instead.
    let notched = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 656, y: 950, width: 200, height: 32),
        hasNotch: true
    )
    check("a notched display hangs from the screen edge", notched.islandTop == 982)

    let notchless = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        notchRect: CGRect(x: 894, y: 1030, width: 132, height: 26),
        hasNotch: false,
        islandTop: 1056
    )
    check("a notchless display hangs below the menu bar", notchless.islandTop < 1080)
    check("the notchless island clears the menu bar", notchless.notchRect.maxY <= notchless.islandTop)

    // Hand corrections: applied on top of the measurement, clamped so a
    // hand-edited file cannot push the island somewhere unreachable.
    var nudge = IslandAdjustment()
    check("no correction means automatic", nudge.isAutomatic)
    check("automatic changes nothing", nudge.applied(to: notched).notchRect == notched.notchRect)

    nudge.horizontal = 40
    check("a sideways nudge moves it", nudge.applied(to: notched).notchRect.midX == notched.notchRect.midX + 40)
    check("a sideways nudge does not resize it", nudge.applied(to: notched).notchRect.width == 200)

    nudge = IslandAdjustment()
    nudge.vertical = 30
    let lowered = nudge.applied(to: notched)
    check("a downward nudge lowers the island", lowered.islandTop == notched.islandTop - 30)
    check("a downward nudge lowers its rect too", lowered.notchRect.maxY == notched.notchRect.maxY - 30)

    nudge = IslandAdjustment()
    nudge.width = 60
    let widened = nudge.applied(to: notched)
    check("widening grows the island", widened.notchRect.width == 260)
    check("widening keeps it centred", widened.notchRect.midX == notched.notchRect.midX)

    var extreme = IslandAdjustment()
    extreme.horizontal = 9_999
    extreme.vertical = -9_999
    extreme.width = 9_999
    extreme.height = 9_999
    let safe = extreme.clamped
    check("a wild sideways value is clamped", safe.horizontal == IslandAdjustment.horizontalRange.upperBound)
    check("a wild upward value is clamped", safe.vertical == IslandAdjustment.verticalRange.lowerBound)
    check("a wild width is clamped", safe.width == IslandAdjustment.widthRange.upperBound)
    check("a wild height is clamped", safe.height == IslandAdjustment.heightRange.upperBound)
    check("clamping happens before it is applied", extreme.applied(to: notched).notchRect.width <= 200 + IslandAdjustment.widthRange.upperBound)

    // Corrections are per display, so one screen's fix never follows onto
    // another, and resetting removes the entry rather than storing zeroes.
    let posSuite = "hashdisland.checks.position.\(UUID().uuidString)"
    let posDefaults = UserDefaults(suiteName: posSuite)!
    let positioned = SettingsStore(defaults: posDefaults)
    var laptop = IslandAdjustment()
    laptop.horizontal = 12
    positioned.setAdjustment(laptop, for: "display-1")
    check("a correction is kept for its display", positioned.adjustment(for: "display-1").horizontal == 12)
    check("another display is untouched", positioned.adjustment(for: "display-2").isAutomatic)
    positioned.setAdjustment(IslandAdjustment(), for: "display-1")
    check("resetting clears the entry", positioned.adjustments["display-1"] == nil)

    positioned.setAdjustment(laptop, for: "display-1")
    positioned.flush()
    let reloadedPositions = SettingsStore(defaults: posDefaults)
    check("corrections survive a restart", reloadedPositions.adjustment(for: "display-1").horizontal == 12)
    UserDefaults.standard.removePersistentDomain(forName: posSuite)

    // Dragging a Position slider must move the island under your hand. That
    // means the overlay reshapes in place on every value, rather than being
    // rebuilt behind a debounce — which only ever landed once you let go.
    if NotchGeometry.preferredScreen() != nil {
        let liveSuite = "hashdisland.checks.live.\(UUID().uuidString)"
        let liveDefaults = UserDefaults(suiteName: liveSuite)!
        let liveSettings = SettingsStore(defaults: liveDefaults)
        let liveContext = FeatureContext(settings: liveSettings)
        let liveController = NotchWindowController(registry: FeatureRegistry(), context: liveContext)

        let before = liveController.currentWindowFrame
        let key = NotchGeometry.preferredScreen().map { NotchGeometry.displayKey(for: $0) } ?? ""
        var slide = IslandAdjustment()
        slide.horizontal = 50
        liveSettings.setAdjustment(slide, for: key)
        let after = liveController.currentWindowFrame
        check("a correction moves the island immediately", after.midX == before.midX + 50)

        slide.horizontal = 80
        liveSettings.setAdjustment(slide, for: key)
        check(
            "each further value moves it again",
            liveController.currentWindowFrame.midX == before.midX + 80
        )

        liveSettings.setAdjustment(IslandAdjustment(), for: key)
        check("clearing it returns the island", liveController.currentWindowFrame.midX == before.midX)

        var taller = IslandAdjustment()
        taller.height = 20
        liveSettings.setAdjustment(taller, for: key)
        check(
            "a size correction resizes it immediately",
            liveController.currentWindowFrame.height > before.height
        )
        liveSettings.setAdjustment(IslandAdjustment(), for: key)
        UserDefaults.standard.removePersistentDomain(forName: liveSuite)
    } else {
        print("  note no screen attached, live-adjustment checks skipped")
    }

    // Reordering: dragging one indicator onto another moves it there, and a
    // drag that makes no sense leaves the order alone rather than corrupting it.
    let order = ["media", "tokens", "network", "battery"]
    check(
        "dragging down moves the row",
        SettingsReorder.moving("media", before: "network", in: order)
            == ["tokens", "network", "media", "battery"]
    )
    check(
        "dragging up moves the row",
        SettingsReorder.moving("battery", before: "tokens", in: order)
            == ["media", "battery", "tokens", "network"]
    )
    check(
        "dropping on itself changes nothing",
        SettingsReorder.moving("media", before: "media", in: order) == order
    )
    check(
        "an unknown row changes nothing",
        SettingsReorder.moving("ghost", before: "media", in: order) == order
    )
    check(
        "reordering never loses or duplicates a row",
        Set(SettingsReorder.moving("media", before: "battery", in: order)) == Set(order)
            && SettingsReorder.moving("media", before: "battery", in: order).count == order.count
    )

    // Battery saver is one number in one place, and it is the number every
    // sampler multiplies by.
    let scaleSuite = "hashdisland.checks.scale.\(UUID().uuidString)"
    let scaleDefaults = UserDefaults(suiteName: scaleSuite)!
    let scaled = SettingsStore(defaults: scaleDefaults)
    check("normally everything samples at its own rate", scaled.samplingScale == 1)
    scaled.batterySaver = true
    check("battery saver halves how often things sample", scaled.samplingScale == 2)

    // An accent id that no longer exists must still leave the island tinted.
    check("a known accent resolves", AccentColor.named("green").name == "Green")
    check("an unknown accent falls back", AccentColor.named("chartreuse").id == AccentColor.default.id)
    check("the default accent is in the list", AccentColor.all.contains { $0.id == AccentColor.default.id })

    // Appearance and alert choices survive a restart.
    scaled.appearance.accentID = "purple"
    scaled.appearance.panelFill = .solid
    scaled.appearance.motion = .calm
    scaled.alerts.noticeSeconds = 7
    scaled.flush()
    let reopened = SettingsStore(defaults: scaleDefaults)
    check("the accent is remembered", reopened.appearance.accentID == "purple")
    check("the panel fill is remembered", reopened.appearance.panelFill == .solid)
    check("the motion is remembered", reopened.appearance.motion == .calm)
    check("the alert length is remembered", reopened.alerts.noticeSeconds == 7)
    check("battery saver is remembered", reopened.batterySaver)
    check("calm motion is slower than lively",
          AppearanceSettings.Motion.calm.responseScale > AppearanceSettings.Motion.lively.responseScale)
    UserDefaults.standard.removePersistentDomain(forName: scaleSuite)

    // The reader's chosen alert length overrides whatever the poster suggested.
    let posted = LiveActivity(
        id: "p", icon: "checkmark", title: "Done", subtitle: nil,
        progress: nil, endsAt: nil, dismissAfter: 3
    )
    let start = Date()
    check(
        "the poster's length is used when there is no preference",
        posted.dismissalDate(firstSeen: start) == start.addingTimeInterval(3)
    )
    check(
        "your preference wins over the poster's",
        posted.dismissalDate(firstSeen: start, preferring: 8) == start.addingTimeInterval(8)
    )
    let countdown = LiveActivity(
        id: "c", icon: "bicycle", title: "Delivery", subtitle: nil,
        progress: nil, endsAt: Date().addingTimeInterval(600), dismissAfter: nil
    )
    check(
        "a countdown is never cut short by the notice preference",
        countdown.dismissalDate(firstSeen: start, preferring: 8) == nil
    )

    // Renaming the app changes the preferences domain, so settings saved under
    // the old name must be carried over exactly once and rewritten under the new
    // key — otherwise an existing install silently comes back reset.
    let legacySuite = "hashdisland.checks.legacy.\(UUID().uuidString)"
    let freshSuite = "hashdisland.checks.fresh.\(UUID().uuidString)"
    let emptySuite = "hashdisland.checks.empty.\(UUID().uuidString)"
    let noLegacySuite = "hashdisland.checks.nolegacy.\(UUID().uuidString)"
    let legacyDefaults = UserDefaults(suiteName: legacySuite)!
    let freshDefaults = UserDefaults(suiteName: freshSuite)!
    let legacyDocument = """
    {"features":{"x":{"enabled":false,"placement":"trailing","styleID":"word","order":4}},"launchAtLogin":true}
    """
    legacyDefaults.set(Data(legacyDocument.utf8), forKey: "hashnotch.settings.v2")

    let migrated = SettingsStore(defaults: freshDefaults, legacyDefaults: legacyDefaults)
    check("settings carry over from the old name", migrated.isEnabled("x") == false)
    check("settings carry over the style", migrated.style(for: "x") == "word")
    check("settings carry over launch at login", migrated.launchAtLogin)
    check("carried-over settings are not a first run", migrated.isFirstRun == false)
    migrated.flush()
    check(
        "carried-over settings are rewritten under the new key",
        freshDefaults.data(forKey: "hashdisland.settings.v2") != nil
    )

    // Once rewritten, the old copy is never needed again.
    legacyDefaults.removeObject(forKey: "hashnotch.settings.v2")
    let afterMigration = SettingsStore(defaults: freshDefaults, legacyDefaults: legacyDefaults)
    check("settings survive without the old copy", afterMigration.style(for: "x") == "word")

    // A genuinely new install still counts as a first run.
    check(
        "a clean install is still a first run",
        SettingsStore(
            defaults: UserDefaults(suiteName: emptySuite)!,
            legacyDefaults: UserDefaults(suiteName: noLegacySuite)!
        ).isFirstRun
    )

    for name in [legacySuite, freshSuite, emptySuite, noLegacySuite] {
        UserDefaults.standard.removePersistentDomain(forName: name)
    }
}

if failures == 0 {
    print("All checks passed.")
    exit(0)
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
