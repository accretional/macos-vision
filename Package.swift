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
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"]),
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
            ]
        ),
    ]
)
