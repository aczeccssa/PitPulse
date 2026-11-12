// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SharedData",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SharedData", targets: ["SharedData"])
    ],
    targets: [
        .target(name: "SharedData"),
        .testTarget(
            name: "SharedDataTests",
            dependencies: ["SharedData"]
        )
    ]
)
