import Foundation
import SwiftUI
import CoreGraphics
import HashNotchKit
import FeatureMedia

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
    check("artwork refuses http", !ArtworkPolicy.isTrustedURL("http://i.scdn.co/image/abc123"))
    check("artwork refuses other hosts", !ArtworkPolicy.isTrustedURL("https://example.com/a.jpg"))
    check("artwork refuses lookalike host", !ArtworkPolicy.isTrustedURL("https://evilscdn.co/a.jpg"))
    check("artwork refuses file scheme", !ArtworkPolicy.isTrustedURL("file:///etc/passwd"))
    check("artwork refuses garbage", !ArtworkPolicy.isTrustedURL("not a url"))

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
