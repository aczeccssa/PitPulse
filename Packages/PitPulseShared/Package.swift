// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PitPulseShared",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v11)],
    products: [
        .library(name: "PitPulseShared", targets: ["PitPulseShared"])
    ],
    targets: [
        .target(name: "PitPulseShared")
    ]
)
