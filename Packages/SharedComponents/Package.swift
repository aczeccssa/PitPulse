// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SharedComponents",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SharedComponents", targets: ["SharedComponents"])
    ],
    dependencies: [
        .package(path: "../SharedData")
    ],
    targets: [
        .target(
            name: "SharedComponents",
            dependencies: [
                .product(name: "SharedData", package: "SharedData")
            ],
            resources: [.process("Resources")]
        )
    ]
)
