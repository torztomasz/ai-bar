// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIBar", targets: ["AIBar"]),
    ],
    targets: [
        // Foundation-only (plus `os` for locks and logging, `Observation` for the settings store) so every piece of
        // domain logic stays unit-testable without AppKit.
        .target(name: "AIBarCore"),
        .executableTarget(name: "AIBar", dependencies: ["AIBarCore"]),
        .testTarget(name: "AIBarCoreTests", dependencies: ["AIBarCore"]),
    ]
)
