// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MoteKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MoteCore", targets: ["MoteCore"])
    ],
    targets: [
        .target(name: "MoteCore"),
        .testTarget(name: "MoteCoreTests", dependencies: ["MoteCore"]),
    ]
)
