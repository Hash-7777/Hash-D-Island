// swift-tools-version: 6.0
import PackageDescription

// HashDIsland is deliberately split into small, independent modules.
//
//   HashDIslandKit   the core: notch window, HUD layout, and the NotchFeature
//                  plugin contract. It knows nothing about any concrete feature.
//   Feature*       one self-contained module per feature. Each depends only on
//                  HashDIslandKit — never on another feature.
//   HashDIsland      the executable. The ONLY place features are wired together
//                  (see Sources/HashDIsland/FeatureManifest.swift).
//
// To add a feature: add a `Feature<Name>` target below, depend on it from the
// `HashDIsland` target, and register it in FeatureManifest. Nothing in
// HashDIslandKit ever needs to change.
let package = Package(
    name: "HashDIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HashDIsland", targets: ["HashDIsland"])
    ],
    targets: [
        .target(name: "HashDIslandKit"),

        .target(name: "FeatureNetwork", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureBattery", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureThermal", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureTokens", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureMedia", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureActivities", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureTimer", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureDownloads", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureAirPods", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureStorage", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureCPU", dependencies: ["HashDIslandKit"]),
        .target(name: "FeatureMemory", dependencies: ["HashDIslandKit"]),

        .executableTarget(
            name: "HashDIsland",
            dependencies: [
                "HashDIslandKit",
                "FeatureNetwork",
                "FeatureBattery",
                "FeatureThermal",
                "FeatureTokens",
                "FeatureMedia",
                "FeatureActivities",
                "FeatureTimer",
                "FeatureDownloads",
                "FeatureAirPods",
                "FeatureStorage",
                "FeatureCPU",
                "FeatureMemory",
            ]
        ),

        // Lightweight, framework-free checks so the core can be verified with
        // `swift run HashDIslandChecks` even on a machine that only has the
        // Command Line Tools (no XCTest/Swift Testing). Swap for a proper
        // .testTarget once full Xcode is available.
        .executableTarget(
            name: "HashDIslandChecks",
            dependencies: ["HashDIslandKit", "FeatureMedia", "FeatureActivities", "FeatureTokens", "FeatureBattery", "FeatureDownloads", "FeatureAirPods", "FeatureNetwork", "FeatureStorage", "FeatureThermal", "FeatureCPU", "FeatureMemory"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
