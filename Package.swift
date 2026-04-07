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
                .linkedFramework("Cocoa"),
                .linkedFramework("Vision"),
            ]
        ),
    ]
)
