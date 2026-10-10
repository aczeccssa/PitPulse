// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PitPulseOpenNookSpike",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(
            url: "https://github.com/twinkling-reality/opennook.git",
            revision: "2b50b5c3a99df8914e25e199d29bf7aa505f7a59"
        )
    ],
    targets: [
        .executableTarget(
            name: "PitPulseOpenNookSpike",
            dependencies: [.product(name: "NookApp", package: "opennook")]
        )
    ]
)
