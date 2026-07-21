import Foundation
import SwiftUI
import CoreGraphics
@testable import HashNotchKit

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

    // Geometry splits evenly around the notch.
    let state = NotchState(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 656, y: 950, width: 200, height: 32),
        hasNotch: true
    ))
    check("notch width", state.notchWidth == 200)
    check("side width splits around notch", state.sideWidth == (1512 - 200) / 2)

    // Rate formatter scales units.
    check("rate B", Formatters.rate(512).unit == "B/s")
    check("rate KB", Formatters.rate(9_216).value == "9" && Formatters.rate(9_216).unit == "KB/s")
    check("rate MB", Formatters.rate(5_242_880).unit == "MB/s")
}

if failures == 0 {
    print("All checks passed.")
    exit(0)
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
