// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MoteKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MoteCore", targets: ["MoteCore"]),
        .library(name: "MoteAI", targets: ["MoteAI"]),
    ],
    targets: [
        .target(name: "MoteCore"),
        .testTarget(name: "MoteCoreTests", dependencies: ["MoteCore"]),
        // Talking to language models: cloud APIs, local servers and the coding
        // agents installed on the Mac, behind one streaming interface.
        .target(name: "MoteAI"),
        .testTarget(name: "MoteAITests", dependencies: ["MoteAI"]),
    ]
)
