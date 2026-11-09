// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PitPulseData",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v11)],
    products: [
        .library(name: "PitPulseData", targets: ["PitPulseData"])
    ],
    dependencies: [
        .package(path: "../PitPulseShared")
    ],
    targets: [
        .target(
            name: "PitPulseData",
            dependencies: [
                .product(name: "PitPulseShared", package: "PitPulseShared")
            ]
        )
    ]
)
