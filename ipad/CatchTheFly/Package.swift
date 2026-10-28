// swift-tools-version: 5.9

// The manifest of the downloadable CatchTheFly.swiftpm (see docs/IPAD_DOWNLOAD.md).
// scripts/pack-swiftpm.sh copies it into the project next to App/ and FlyCore/.
// The format follows what Swift Playgrounds writes itself, checked against real
// Playgrounds projects on GitHub on 2026-10-28 (capability and icon names included).
// Once the project is open, Playgrounds owns this file: change settings in the app,
// or change this template and download a fresh copy.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "CatchTheFly",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .iOSApplication(
            name: "CatchTheFly",
            targets: ["AppModule"],
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .sparkle),
            accentColor: .presetColor(.green),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .camera(purposeString: "Catch the Fly uses the camera to show the room around you, so you can hunt the fly in it. Nothing is recorded or uploaded."),
                .motion(purposeString: "Catch the Fly uses motion data to follow how you turn and move the phone while you stalk the fly.")
            ],
            appCategory: .games
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
