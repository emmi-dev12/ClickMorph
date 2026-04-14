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
            // Info.plist is copied into the .app bundle by the Makefile;
            // SPM forbids it as a top-level resource, so exclude it here.
            exclude: ["Resources/Info.plist"]
        )
    ]
)
