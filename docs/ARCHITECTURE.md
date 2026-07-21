# Architecture

HashNotch is built so that every capability is a **plug-in**. The core knows how
to draw a HUD around the notch and how to talk to a feature through one small
protocol — it never knows what any feature actually does. That is what lets
features be added or removed without editing the core.

## Modules

```
HashNotchKit      Core framework. Notch detection, the overlay window, the HUD
                  layout, the theme, and the NotchFeature contract.
                  Depends on nothing in this repo.

FeatureNetwork    One self-contained feature each. Every feature module depends
FeatureBattery    only on HashNotchKit — never on another feature.
FeatureThermal

HashNotch         The executable. The only place features are wired together.
                  Depends on the core + every feature it enables.

HashNotchChecks   Framework-free checks for the core, runnable under the
                  Command Line Tools (`swift run HashNotchChecks`).
```

Dependencies only ever point **inward** toward the core:

```
FeatureNetwork ─┐
FeatureBattery ─┼─▶ HashNotchKit
FeatureThermal ─┘
       ▲
HashNotch ──────┘   (also depends on each feature, to register them)
```

## The feature contract

Every feature implements `NotchFeature` (in `HashNotchKit`):

```swift
@MainActor
public protocol NotchFeature: AnyObject {
    var id: String { get }
    var title: String { get }
    var placement: FeaturePlacement { get }   // .leading / .trailing / .expanded
    func makeView(context: FeatureContext) -> AnyView
    func start()   // begin sampling
    func stop()    // release resources
}
```

A feature owns its own data source (an `ObservableObject` monitor) and its own
SwiftUI view. The core collects features from the `FeatureRegistry`, lays out the
compact readouts either side of the notch, and drives `start()` / `stop()`.

## How the pieces fit at launch

```
main.swift
  └─ AppDelegate
       ├─ FeatureManifest.enabledFeatures()   ← the list of features to turn on
       ├─ FeatureRegistry.register(…) + startAll()
       └─ NotchWindowController
            ├─ NotchGeometry   measures the physical notch
            ├─ NotchWindow     transparent overlay above the menu bar
            └─ NotchContainerView (SwiftUI)
                 └─ asks the registry for each feature's view
```

## Adding a feature

1. Create `Sources/Feature<Name>/` with:
   - a `Monitor` (`ObservableObject`) that samples your data,
   - a SwiftUI `View`,
   - a type conforming to `NotchFeature` that ties them together.
2. In `Package.swift`, add a `.target(name: "Feature<Name>", dependencies:
   ["HashNotchKit"])` and add `"Feature<Name>"` to the `HashNotch` target's
   dependencies.
3. In `Sources/HashNotch/FeatureManifest.swift`, `import Feature<Name>` and add
   one line to the returned array.

The core (`HashNotchKit`) does not change.

## Removing a feature

Delete its line from `FeatureManifest.swift`. Optionally delete the module folder
and its `Package.swift` entries. Nothing else is affected.

## Why this shape

- **Isolation** — a bug or a rewrite in one feature can't reach another; the
  compiler enforces the module boundaries.
- **Scale** — new features are additive. The core and existing features stay
  untouched, so the risk of each addition stays flat as the app grows.
- **Testability** — the core is verified against a stub feature, with no real
  feature present, proving the decoupling holds.
