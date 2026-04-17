// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "macos-vision",
    platforms: [
        .macOS(.v10_15)
    ],
    targets: [
        .executableTarget(
            name: "macos-vision",
            path: "Sources",
            cSettings: [
                .headerSearchPath("."),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Vision"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Speech"),
                .linkedFramework("SoundAnalysis"),
                .linkedFramework("ShazamKit"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("CoreML"),
                .linkedFramework("ImageCaptureCore"),
            ]
        ),
    ]
)
