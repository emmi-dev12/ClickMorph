// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClickMorph",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClickMorph",
            path: "Sources/ClickMorph",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
