// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AIBarCore", targets: ["AIBarCore"]),
    ],
    targets: [
        // Foundation-only so every piece of domain logic stays unit-testable without AppKit.
        .target(name: "AIBarCore"),
        .testTarget(name: "AIBarCoreTests", dependencies: ["AIBarCore"]),
    ]
)
