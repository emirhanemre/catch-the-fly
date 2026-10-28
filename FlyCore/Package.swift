// swift-tools-version:6.0
import PackageDescription

// The library builds in the Swift 6 language mode (strict concurrency), the same mode the iPad's
// Swift Playgrounds app module uses, so concurrency errors show up on Windows first.
// The tests stay in the Swift 5 mode to avoid XCTest isolation differences between platforms.
let package = Package(
    name: "FlyCore",
    products: [
        .library(name: "FlyCore", targets: ["FlyCore"])
    ],
    targets: [
        .target(name: "FlyCore"),
        .testTarget(name: "FlyCoreTests",
                    dependencies: ["FlyCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
