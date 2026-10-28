// swift-tools-version: 5.9

// The manifest of the downloadable DuoProbe.swiftpm (see docs/IPAD_DOWNLOAD.md).
// scripts/pack-swiftpm.sh copies it into the project next to App/. DuoProbe doesn't
// use FlyCore. Same format notes as ipad/CatchTheFly/Package.swift.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "DuoProbe",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .iOSApplication(
            name: "DuoProbe",
            targets: ["AppModule"],
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .earth),
            accentColor: .presetColor(.blue),
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
                .camera(purposeString: "DuoProbe uses the cameras to test what this iPhone's cameras can see. Images stay on the phone unless you share the log."),
                .motion(purposeString: "DuoProbe uses motion data to measure how the phone moves while it opens and closes."),
                .photoLibraryAdd(purposeString: "DuoProbe saves its test clips to your photo library when you choose Save Video.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
