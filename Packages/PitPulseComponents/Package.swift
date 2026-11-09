// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PitPulseComponents",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v11)],
    products: [
        .library(name: "PitPulseComponents", targets: ["PitPulseComponents"])
    ],
    dependencies: [
        .package(path: "../PitPulseShared")
    ],
    targets: [
        .target(
            name: "PitPulseComponents",
            dependencies: [
                .product(name: "PitPulseShared", package: "PitPulseShared")
            ]
        )
    ]
)
