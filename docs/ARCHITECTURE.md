# Architecture

Hash D Island is built so that every capability is a **plug-in**. The core knows how
to draw an island around the notch and how to talk to a feature through one small
protocol — it never knows what any feature actually does. That is what lets
features be added or removed without editing the core.

## Modules

```
HashDIslandKit      Core framework. Notch detection, the overlay window, the
                  island and panel, the theme, shared UI pieces, settings, and
                  the NotchFeature contract. Depends on nothing in this repo.

FeatureMedia      One self-contained feature each. Every feature module depends
FeatureActivities only on HashDIslandKit — never on another feature.
FeatureDownloads
FeatureTimer
FeatureTokens
FeatureNetwork
FeatureBattery
FeatureAirPods
FeatureThermal

Hash D Island         The executable. The only place features are wired together.
                  Depends on the core + every feature it enables.

HashDIslandChecks   Framework-free checks for the core and the parsers, runnable
                  under the Command Line Tools (`swift run HashDIslandChecks`).
```

Dependencies only ever point **inward** toward the core:

```
FeatureMedia ────┐
FeatureBattery ──┼─▶ HashDIslandKit
… every other ───┘
       ▲
Hash D Island ───────┘   (also depends on each feature, to register them)
```

## The feature contract

Every feature implements `NotchFeature` (in `HashDIslandKit`):

```swift
@MainActor
public protocol NotchFeature: AnyObject {
    var id: String { get }
    var title: String { get }
    var placement: FeaturePlacement { get }
    var displayOptions: [FeatureOption] { get }

    /// Compact readout.
    func makeView(context: FeatureContext) -> AnyView
    /// Richer row for the open panel; nil to show nothing there.
    func makeExpandedView(context: FeatureContext) -> AnyView?
    /// Always-on views flanking the notch while this feature is live;
    /// nil for none.
    func makeCompactLeadingView(context: FeatureContext) -> AnyView?
    func makeCompactTrailingView(context: FeatureContext) -> AnyView?

    func start(context: FeatureContext)   // begin sampling
    func stop()                           // release resources
}
```

Everything but `id`, `title`, `placement` and `makeView` has a default, so a
simple feature implements four members.

A feature owns its own data source (an `ObservableObject` monitor) and its own
SwiftUI views. `FeatureContext` is how it reaches shared services: the settings
store, `LivePresence` (to say "I have something live right now"), and the
closure that opens the settings window.

## The three states

`NotchIslandView` draws three separate layers, stacked, each with its own shape:

- **Collapsed** — a black shape matching the physical notch exactly, so at rest
  the app is invisible.
- **Live** — a slim strip that appears *beside* the notch, at menu-bar height,
  whenever any feature signals `LivePresence`: artwork and title to one side,
  a countdown to the other. No hover needed.
- **Expanded** — a rounded panel that drops straight down below the menu bar,
  listing every enabled feature's `makeExpandedView`, with the settings gear in
  its corner. Because it opens *below* the menu bar, it can never overlap app
  menus or status items.

`NotchWindowController` owns the overlay window and keeps it sized tight to
whichever state is showing, always centered on the notch. It detects hover with
observe-only mouse-position monitors against tight, hysteretic zones (a small
notch-sized zone to open; a keep-open area that must fully contain every zone
that can trigger opening, or the panel flickers at the edges). The window is
click-through in every state except while the panel is open.

Low-power behavior also lives in the core: `PollingSampler` uses tolerant,
coalesced timers; monitors publish only when a displayed value actually changes;
and `PowerCoordinator` stops all sampling while the screen is asleep.

## Customization (settings)

User choices live in `SettingsStore` (in `HashDIslandKit`), persisted to
`UserDefaults`. It is the single source of truth for:

- which features are enabled,
- each feature's chosen display style, and
- open-at-login.

Features declare their display choices via `displayOptions` and read the
selected one with `context.settings.style(for: id)` inside `makeView`. The
island observes the store, so changing a setting updates the notch live.

There is no menu-bar item: `SettingsView` is reached through the gear button in
the expanded panel (`FeatureContext.openSettings`), and it is also where the app
is quit.

## Adding a feature

1. Create `Sources/Feature<Name>/` with:
   - a `Monitor` (`ObservableObject`) that samples your data,
   - a SwiftUI `View`,
   - a type conforming to `NotchFeature` that ties them together.
2. In `Package.swift`, add a `.target(name: "Feature<Name>", dependencies:
   ["HashDIslandKit"])` and add `"Feature<Name>"` to the `Hash D Island` target's
   dependencies.
3. In `Sources/Hash D Island/FeatureManifest.swift`, `import Feature<Name>` and add
   one line to the returned array.

The core (`HashDIslandKit`) does not change.

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
