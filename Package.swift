// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ETS2DualSense",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DualSenseKit", targets: ["DualSenseKit"]),
        .library(name: "EffectKit", targets: ["EffectKit"]),
    ],
    targets: [
        .target(name: "CTelemetry", path: "shared", sources: ["ipc.c"], publicHeadersPath: "."),
        .target(name: "DualSenseKit"),
        .target(name: "EffectKit", dependencies: ["CTelemetry", "DualSenseKit"]),
        .executableTarget(name: "ETS2DualSense", dependencies: ["DualSenseKit", "EffectKit"]),
        .executableTarget(name: "dsprobe", dependencies: ["DualSenseKit", "EffectKit"]),
        .testTarget(name: "DualSenseKitTests", dependencies: ["DualSenseKit"]),
        .testTarget(name: "EffectKitTests", dependencies: ["EffectKit"]),
    ],
    swiftLanguageModes: [.v5]
)
