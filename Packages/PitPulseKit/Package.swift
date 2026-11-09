// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "PitPulseKit",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v11)],
    products: [
        .library(name: "PitPulseShared", targets: ["PitPulseShared"]),
        .library(name: "PitPulseData", targets: ["PitPulseData"]),
        .library(name: "PitPulseComponents", targets: ["PitPulseComponents"])
    ],
    targets: [
        .target(name: "PitPulseShared", path: "Sources/Shared"),
        .target(name: "PitPulseData", dependencies: ["PitPulseShared"], path: "Sources/Data"),
        .target(name: "PitPulseComponents", dependencies: ["PitPulseShared"], path: "Sources/Components")
    ]
)
