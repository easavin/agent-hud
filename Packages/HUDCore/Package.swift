// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HUDCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "HUDCore", targets: ["HUDCore"])],
    targets: [
        .target(name: "HUDCore"),
        .executableTarget(name: "hudctl", dependencies: ["HUDCore"]),
        .testTarget(name: "HUDCoreTests", dependencies: ["HUDCore"]),
    ]
)
