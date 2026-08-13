// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EDIT950",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EDIT950", targets: ["EDIT950"])
    ],
    targets: [
        .executableTarget(
            name: "EDIT950",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMIDI"),
                .linkedFramework("CoreText"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "EDIT950Tests",
            dependencies: ["EDIT950"],
            resources: [.process("Fixtures")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
