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
import FeatureThermal
import FeatureStorage

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

    // Only one feature may own the live strip. Two of them at once is what put
    // "Claude finished" on top of the song title: the pill grew past the width
    // its own centring is derived from and slid across the notch.
    func stripOwner(_ candidates: [(id: String, priority: Int)], live: Set<String>) -> String? {
        var best: (id: String, priority: Int, index: Int)?
        for (index, candidate) in candidates.enumerated() where live.contains(candidate.id) {
            if let current = best,
               candidate.priority < current.priority
                || (candidate.priority == current.priority && index > current.index) {
                continue
            }
            best = (candidate.id, candidate.priority, index)
        }
        return best?.id
    }

    let strip = [
        (id: "media", priority: LivePriority.ongoing),
        (id: "timer", priority: LivePriority.ongoing),
        (id: "downloads", priority: LivePriority.announcement),
        (id: "activities", priority: LivePriority.needsYou),
    ]
    check("nothing live means nothing on the strip", stripOwner(strip, live: []) == nil)
    check("one live feature owns it", stripOwner(strip, live: ["media"]) == "media")
    check(
        "a finished job takes the strip from the music",
        stripOwner(strip, live: ["media", "activities"]) == "activities"
    )
    check(
        "a battery notice outranks a playing track",
        stripOwner(strip, live: ["media", "downloads"]) == "downloads"
    )
    check(
        "something waiting on you outranks a passing notice",
        stripOwner(strip, live: ["downloads", "activities"]) == "activities"
    )
    check(
        "equal priority falls back to registration order, never to chance",
        stripOwner(strip, live: ["timer", "media"]) == "media"
    )
    check(
        "the strip returns to the music once the notice leaves",
        stripOwner(strip, live: ["media"]) == "media"
    )
    check("an announcement outranks something merely ongoing", LivePriority.announcement > LivePriority.ongoing)
    check("waiting on you outranks an announcement", LivePriority.needsYou > LivePriority.announcement)

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

    // The app an activity names is a capability, so it is bounded like every
    // other field from the feed: a real .app bundle or nothing. Clicking a row
    // may bring a window forward; it may never run a loose executable.
    func appPath(forFeed value: String) -> String? {
        let file = tempFile("[{\"id\":\"A\",\"title\":\"Jump\",\"app\":\"\(value)\"}]")
        defer { try? FileManager.default.removeItem(at: file) }
        return ActivitiesReader.read(from: file).first?.appPath
    }

    let fakeApp = logoDir.appendingPathComponent("Pretend.app")
    try? FileManager.default.createDirectory(at: fakeApp, withIntermediateDirectories: true)
    check("a real app bundle is accepted", appPath(forFeed: fakeApp.path) == fakeApp.path)
    check("a loose executable is refused", appPath(forFeed: "/bin/sh") == nil)
    check("a plain file named .app is refused", appPath(forFeed: notAnImage.path) == nil)
    check("a missing bundle is refused", appPath(forFeed: logoDir.appendingPathComponent("Gone.app").path) == nil)
    check("an empty app path is refused", appPath(forFeed: "") == nil)
    check(
        "an app path that climbs out is resolved before it is judged",
        appPath(forFeed: logoDir.appendingPathComponent("../../../bin/sh").path) == nil
    )
    check(
        "an activity that names no app simply has none",
        ActivitiesReader.read(from: tempFile("[{\"id\":\"N\",\"title\":\"None\"}]"))
            .first?.appPath == nil
    )

    // A notice's few seconds must start when THAT notice arrives. Posters reuse
    // an id on purpose — it is how the feed merges — so judging a new alert by
    // the id alone measured it against the PREVIOUS one's clock, found it long
    // past, and dropped it before it ever drew. Every repeat alert vanished in
    // silence, which is the worst way for an alert to fail.
    func notice(_ id: String, endsAt: String) -> LiveActivity {
        LiveActivity(
            id: id, icon: "checkmark", title: "Claude finished", subtitle: nil,
            progress: nil, endsAt: ISO8601DateFormatter().date(from: endsAt),
            dismissAfter: 3
        )
    }
    let firstAlert = notice("claude-code", endsAt: "2099-01-01T12:00:03Z")
    let secondAlert = notice("claude-code", endsAt: "2099-01-01T12:05:41Z")

    check(
        "a notice never seen before starts its clock",
        ActivitiesMonitor.startsFresh(firstAlert, previously: nil)
    )
    check(
        "re-reading the same notice does not restart its clock",
        ActivitiesMonitor.startsFresh(firstAlert, previously: firstAlert) == false
    )
    check(
        "a later alert reusing the same id starts its own clock",
        ActivitiesMonitor.startsFresh(secondAlert, previously: firstAlert)
    )
    check(
        "a countdown keeps no notice clock at all",
        ActivitiesMonitor.startsFresh(
            LiveActivity(
                id: "c", icon: "bicycle", title: "Delivery", subtitle: nil, progress: nil,
                endsAt: Date().addingTimeInterval(600), dismissAfter: nil
            ),
            previously: nil
        ) == false
    )
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
    check("plugging in is not a warning", BatteryEvent.pluggedIn(50).isWarning == false)
    check("fully charged is not a warning", BatteryEvent.fullyCharged(100).isWarning == false)
    check("unplugging is not a warning", BatteryEvent.unplugged(80).isWarning == false)

    // Plugging in announces on the POWER transition, not on reaching the
    // charging state. macOS reports external power the instant the cable goes
    // in while IsCharging is still false, so the real sequence is
    // discharging → held → charging. Keying the announcement on "reached
    // charging" matched none of it, and the plug-in alert never fired while
    // unplugging — which has no such in-between step — announced every time.
    func announces(from previous: BatteryState, to next: BatteryState) -> String? {
        guard previous != next else { return nil }
        let wasOnPower = previous != .discharging
        let isOnPower = next != .discharging
        if isOnPower != wasOnPower { return isOnPower ? "pluggedIn" : "unplugged" }
        if previous == .charging, next == .charged || next == .onHold { return "fullyCharged" }
        return nil
    }
    check(
        "the cable going in announces even when charging has not begun yet",
        announces(from: .discharging, to: .onHold) == "pluggedIn"
    )
    check(
        "plugging in straight into a charge announces once",
        announces(from: .discharging, to: .charging) == "pluggedIn"
    )
    check(
        "plugging in at full announces",
        announces(from: .discharging, to: .charged) == "pluggedIn"
    )
    check(
        "settling from held into charging does not announce again",
        announces(from: .onHold, to: .charging) == nil
    )
    check(
        "pulling the cable announces",
        announces(from: .charging, to: .discharging) == "unplugged"
    )
    check(
        "finishing the charge announces",
        announces(from: .charging, to: .charged) == "fullyCharged"
    )
    check(
        "a health hold at the end of a charge announces",
        announces(from: .charging, to: .onHold) == "fullyCharged"
    )
    check("nothing changed, nothing announced", announces(from: .charging, to: .charging) == nil)

    // Charge speed is judged on the adapter's own rating, and claims nothing
    // when the adapter reports none.
    check("a phone charger is slow", BatteryMonitor.ChargeSpeed.forWatts(12) == .slow)
    check("20W is where a charger stops being a phone charger", BatteryMonitor.ChargeSpeed.forWatts(20) == .standard)
    // 29 and 30 are both real Apple adapters and both the stock supply for a
    // laptop this size. Calling either of them slow, for want of being the
    // biggest one sold, would be wrong about a charger doing its job.
    check("a 29W adapter is not slow", BatteryMonitor.ChargeSpeed.forWatts(29) == .standard)
    check("a 30W adapter is not slow", BatteryMonitor.ChargeSpeed.forWatts(30) == .standard)
    check("an everyday adapter is standard", BatteryMonitor.ChargeSpeed.forWatts(35) == .standard)
    check("a big adapter is fast", BatteryMonitor.ChargeSpeed.forWatts(96) == .fast)
    check("the fast threshold is 60W", BatteryMonitor.ChargeSpeed.forWatts(60) == .fast)
    check("no rating claims no speed", BatteryMonitor.ChargeSpeed.forWatts(0) == nil)

    // After the cable moves, the app keeps re-reading until there is nothing
    // left to wait for. A fixed burst was the wrong shape: charging can begin a
    // second or a minute after the cable goes in, and macOS may take several
    // minutes to estimate a time to full — its own menu says "no estimate"
    // meanwhile. Stopping on a clock left the panel holding its first
    // impression, which is how "held for battery health" survived on screen
    // while the menu bar said charging.
    check(
        "on battery there is nothing to wait for",
        BatteryMonitor.isSettled(state: .discharging, minutesToFull: nil)
    )
    check(
        "a full battery is settled",
        BatteryMonitor.isSettled(state: .charged, minutesToFull: nil)
    )
    check(
        "charging without an estimate keeps watching",
        BatteryMonitor.isSettled(state: .charging, minutesToFull: nil) == false
    )
    check(
        "charging with an estimate is settled",
        BatteryMonitor.isSettled(state: .charging, minutesToFull: 89)
    )
    check(
        "a hold keeps watching, in case it is only the adapter negotiating",
        BatteryMonitor.isSettled(state: .onHold, minutesToFull: nil) == false
    )

    // The charge ceiling is learned from behaviour, because macOS publishes no
    // way to ask. A Mac on power that has deliberately stopped short of full
    // has shown you its limit.
    check(
        "a hold below full teaches the ceiling",
        BatteryMonitor.ceiling(after: .onHold, percentage: 80, known: nil) == 80
    )
    check(
        "any limit is learned, not just eighty",
        BatteryMonitor.ceiling(after: .onHold, percentage: 60, known: nil) == 60
    )
    check(
        "a Mac sitting at 99 has finished, not been limited",
        BatteryMonitor.ceiling(after: .onHold, percentage: 99, known: nil) == nil
    )
    check(
        "charging below a known ceiling keeps it",
        BatteryMonitor.ceiling(after: .charging, percentage: 62, known: 80) == 80
    )
    check(
        "climbing past the ceiling unlearns it",
        BatteryMonitor.ceiling(after: .charging, percentage: 88, known: 80) == nil
    )
    check(
        "reaching full clears any ceiling",
        BatteryMonitor.ceiling(after: .charged, percentage: 100, known: 80) == nil
    )
    check(
        "unplugging changes nothing about the ceiling",
        BatteryMonitor.ceiling(after: .discharging, percentage: 47, known: 80) == 80
    )

    // Time is then counted to that level rather than to a full battery it will
    // never reach.
    check(
        "the estimate is scaled to the ceiling",
        // 51 points of climb left to full in 102 minutes is 2 min per point;
        // the 31 points up to 80% should read as about an hour.
        BatteryMonitor.minutesToCeiling(minutesToFull: 102, percentage: 49, ceiling: 80) == 62
    )
    check(
        "no ceiling means the estimate is left alone",
        BatteryMonitor.minutesToCeiling(minutesToFull: 102, percentage: 49, ceiling: nil) == nil
    )
    check(
        "a ceiling of 100 is not a ceiling",
        BatteryMonitor.minutesToCeiling(minutesToFull: 102, percentage: 49, ceiling: 100) == nil
    )
    check(
        "already at the ceiling means nothing left to count",
        BatteryMonitor.minutesToCeiling(minutesToFull: 102, percentage: 80, ceiling: 80) == nil
    )
    check(
        "no estimate to scale, no answer invented",
        BatteryMonitor.minutesToCeiling(minutesToFull: nil, percentage: 49, ceiling: 80) == nil
    )
    check(
        "a sliver of climb left never rounds down to nothing",
        // 10 minutes of climb spread over 21 points, of which one is wanted,
        // comes to under half a minute — which must still read as a minute
        // rather than as no time at all.
        BatteryMonitor.minutesToCeiling(minutesToFull: 10, percentage: 79, ceiling: 80) == 1
    )

    // A label drawn ON the accent has to stay readable, and White is one of
    // the accents on offer — which made the timer's Start button an empty
    // capsule. Judged on perceived brightness so an accent added later is
    // handled without anyone remembering this rule exists.
    check("white is a light accent", AccentColor.named("white").isLight)
    check("blue is not", AccentColor.named("blue").isLight == false)
    // Green looked like it should take white text and does not: white on that
    // green is about 1.75:1, black about 12:1. Trusting the arithmetic over the
    // impression is the entire reason this is computed rather than listed.
    check("green needs dark text too", AccentColor.named("green").isLight)
    check("purple is not", AccentColor.named("purple").isLight == false)
    check("orange is light enough to need dark text", AccentColor.named("orange").isLight)

    // Every style a feature offers must be one the panel can actually render.
    // The display styles were inert for a long time — the panel draws only the
    // expanded view, and none of those took a style — so a setting that changed
    // nothing sat in the Indicators list for every one of them.
    let styleFeatures: [(String, [String])] = [
        ("network", ["both", "downloadOnly", "uploadOnly", "stacked", "compact"]),
        ("battery", ["iconAndPercent", "percent", "icon", "timeRemaining"]),
        ("thermal", ["symbolAndNumber", "number", "word", "symbol"]),
        ("tokens", ["number", "labeled"]),
    ]
    // Built here rather than read from the app's manifest, which lives in the
    // executable and is not importable.
    let manifest: [NotchFeature] = [
        NetworkFeature(), BatteryFeature(), ThermalFeature(), TokensFeature(),
    ]
    var everyOptionIsKnown = true
    for (id, known) in styleFeatures {
        guard let feature = manifest.first(where: { $0.id == id }) else { everyOptionIsKnown = false; continue }
        for option in feature.displayOptions where !known.contains(option.id) {
            everyOptionIsKnown = false
        }
    }
    check("every offered display style is one the panel knows", everyOptionIsKnown)
    check(
        "the features that offer styles are the ones expected to",
        Set(manifest.filter { !$0.displayOptions.isEmpty }.map(\.id))
            == Set(styleFeatures.map(\.0))
    )

    // Temperature can be read as a word instead of a number.
    check("a cool die reads Cool", ThermalWording.word(for: 42) == "Cool")
    check("a working die reads Warm", ThermalWording.word(for: 62) == "Warm")
    check("a hot die reads Hot", ThermalWording.word(for: 78) == "Hot")
    check("a very hot die says so", ThermalWording.word(for: 95) == "Very hot")

    // Whether the app can be a login item is a question about the BUNDLE, not
    // about whether it is already registered. Asking the registration made the
    // switch disable itself for exactly the people trying to switch it on: a
    // never-registered app reports notFound, which the old test read as "this
    // Mac cannot do it", and nothing else ever registers it.
    //
    // These checks run from a bare executable with no bundle identifier, which
    // is the case that genuinely cannot register — so this asserts the honest
    // answer for the process actually asking.
    check("a bare binary cannot be a login item", LoginItem.isSupported == false)
    check("and does not claim to be enabled", LoginItem.isEnabled == false)
    check(
        "the bundle is what decides, and this has none",
        Bundle.main.bundleIdentifier == nil || Bundle.main.bundleURL.pathExtension != "app"
    )

    // Storage: the sums behind "62% full, 91.5 GB free".
    let disk = DiskUsage(name: "Macintosh HD", totalBytes: 245_107_195_904, availableBytes: 91_530_000_000)
    check("used is what is not available", disk.usedBytes == 245_107_195_904 - 91_530_000_000)
    check("percent full is rounded to a whole number", disk.percentUsed == 63)
    check(
        "an empty disk is not full",
        DiskUsage(name: "x", totalBytes: 1_000, availableBytes: 1_000).percentUsed == 0
    )
    check(
        "a full disk reads 100",
        DiskUsage(name: "x", totalBytes: 1_000, availableBytes: 0).percentUsed == 100
    )
    check(
        "a volume reporting no size divides by nothing rather than crashing",
        DiskUsage(name: "x", totalBytes: 0, availableBytes: 0).percentUsed == 0
    )
    check(
        "free space is never reported as more than the disk holds",
        StorageReader.read(volume: StorageReader.volumeURL).map { $0.availableBytes <= $0.totalBytes } ?? true
    )
    check("the real startup disk reads back", StorageReader.read(volume: StorageReader.volumeURL) != nil)

    // Sizes are shown in the units macOS uses — powers of a thousand, so the
    // number matches the one Finder is showing on the same disk.
    check("bytes stay bytes", Formatters.bytes(512) == "512 B")
    check("thousands are kilobytes", Formatters.bytes(49_000) == "49 KB")
    check("millions are megabytes", Formatters.bytes(5_500_000) == "5.5 MB")
    check("billions are gigabytes", Formatters.bytes(91_530_000_000) == "91.53 GB")
    check("trillions are terabytes", Formatters.bytes(2_000_000_000_000) == "2 TB")
    check("a negative size is not shown as negative", Formatters.bytes(-5) == "0 B")

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

        // Only the notch opens the panel. The live strip reaches far past it —
        // its trailing side alone is 170 points — and the menu bar's own status
        // items sit in exactly that space, so treating the strip as a trigger
        // meant reaching for the camera or Wi-Fi icon opened the panel over the
        // thing being reached for.
        let zone = liveController.openZone
        let notch = liveController.currentNotchRect
        check(
            "the opening zone is the notch, not the strip",
            zone.width <= notch.width + 16
        )
        check(
            "a status item to the right of the strip cannot open the panel",
            zone.contains(CGPoint(x: notch.midX + 170, y: notch.midY)) == false
        )
        check(
            "nor one to the left of it",
            zone.contains(CGPoint(x: notch.midX - 170, y: notch.midY)) == false
        )
        check(
            "the notch itself still opens it",
            zone.contains(CGPoint(x: notch.midX, y: notch.maxY - 2))
        )
        // The invariant that stops it flapping: anything that can open the
        // panel must also be able to keep it open.
        check(
            "whatever opens it can keep it open",
            liveController.keepOpenZone.contains(zone.origin)
                && liveController.keepOpenZone.union(zone) == liveController.keepOpenZone
        )

        // The keep-open zone has to reach the bottom of the panel as it really
        // is, not as the nominal height says. The panel grows with whatever is
        // switched on; a zone fixed at 460 covered the top two thirds of a tall
        // one, so the cursor left it before reaching the last row and the panel
        // shut on the way there. The timer is ordered last, so the timer was
        // the row nobody could reach.
        let tallPanel: CGFloat = 640
        let tallZone = NotchWindowController.expandedZone(
            notchRect: notch, islandTop: notch.maxY, width: 300, height: tallPanel
        )
        check(
            "the keep-open zone reaches the bottom of a tall panel",
            tallZone.contains(CGPoint(x: notch.midX, y: notch.maxY - tallPanel + 2))
        )
        check(
            "and a little past it, for a cursor arriving slowly",
            tallZone.contains(CGPoint(x: notch.midX, y: notch.maxY - tallPanel - 6))
        )
        check(
            "a taller panel gets a taller zone",
            NotchWindowController.expandedZone(
                notchRect: notch, islandTop: notch.maxY, width: 300, height: 640
            ).height > NotchWindowController.expandedZone(
                notchRect: notch, islandTop: notch.maxY, width: 300, height: 460
            ).height
        )
        check(
            "the zone still hangs from the island's top edge",
            tallZone.maxY == notch.maxY
        )

        // The alignment invariant, swept across every height a panel could
        // plausibly reach. The window frame and the keep-open zone are two
        // consumers of one measurement, and this bug has now appeared twice
        // from them working it out separately — so rather than fixing the
        // second instance and hoping, the agreement itself is what is checked.
        let screen = NotchGeometry.preferredScreen()?.frame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let top = notch.maxY
        var aligned = true
        var capped = true
        var reaches = true
        for measured in stride(from: CGFloat(200), through: 2000, by: 37) {
            let height = NotchWindowController.expandedContentHeight(
                measured: measured, islandTop: top, screenFrame: screen
            )
            // Never taller than the room below the island.
            if height > top - screen.minY - NotchWindowController.panelBottomMargin + 0.5 {
                capped = false
            }
            // Never taller than the content asked for.
            if height > measured + 0.5 { aligned = false }
            // The zone must reach the bottom of whatever height was settled on.
            let zone = NotchWindowController.expandedZone(
                notchRect: notch, islandTop: top, width: 300, height: height
            )
            if !zone.contains(CGPoint(x: notch.midX, y: top - height + 1)) { reaches = false }
        }
        check("the panel never exceeds the room below the island", capped)
        check("nor claims more height than its content asked for", aligned)
        check("the keep-open zone reaches the bottom at every height", reaches)
        check(
            "an absurd panel is capped rather than run off the screen",
            NotchWindowController.expandedContentHeight(
                measured: 5000, islandTop: top, screenFrame: screen
            ) == top - screen.minY - NotchWindowController.panelBottomMargin
        )
        check(
            "the room below the island is what limits it, not the screen's height",
            NotchWindowController.expandedContentHeight(
                measured: 5000, islandTop: top, screenFrame: screen
            ) > screen.height * 0.8
        )

        // Settings hangs off the panel's right edge, sharing its top edge so
        // the two read as one surface rather than as a window that happened to
        // appear nearby.
        let panel = CGRect(x: 490, y: 315, width: 300, height: 517)
        let roomy = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let beside = SettingsWindowController.frame(besideAnchor: panel, in: roomy)
        check("settings hangs from the panel's top edge", beside.maxY == panel.maxY)
        check("settings sits to the right of the panel", beside.minX > panel.maxX)
        check("with a gap, not touching", beside.minX - panel.maxX >= 8)

        // A laptop display has far less room to the right than a desk monitor,
        // and running off the screen is worse than overlapping the island.
        let tight = CGRect(x: 0, y: 0, width: 1280, height: 832)
        let clamped = SettingsWindowController.frame(
            besideAnchor: CGRect(x: 490, y: 315, width: 300, height: 517), in: tight
        )
        check("it never runs off the right edge", clamped.maxX <= tight.maxX)
        check("nor off the left", clamped.minX >= tight.minX)

        // Hung from the top of a panel on a short screen, it shortens rather
        // than hanging past the bottom of the display.
        let short = CGRect(x: 0, y: 0, width: 1280, height: 700)
        let shortened = SettingsWindowController.frame(
            besideAnchor: CGRect(x: 490, y: 200, width: 300, height: 500), in: short
        )
        check("it never hangs below the screen", shortened.minY >= short.minY)

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
