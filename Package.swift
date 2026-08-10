// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Islet", targets: ["Islet"]),
        // Named `islet-cli` rather than `islet`: macOS filesystems are
        // case-insensitive, so a product called `islet` collides with the
        // `Islet` app target's build directory. `make app` installs the binary
        // into the bundle as plain `islet`.
        .executable(name: "islet-cli", targets: ["IsletCLI"]),
        .library(name: "IsletCore", targets: ["IsletCore"]),
    ],
    targets: [
        // Pure model + engine. No AppKit, no SwiftUI — this is what the CLI
        // links against too, so it must stay UI-free and portable.
        .target(name: "IsletCore"),

        // The island itself: window, shape, morph, presentations.
        .target(name: "IsletUI", dependencies: ["IsletCore"]),

        // Built-in providers that feed system state into the engine.
        .target(name: "IsletModules", dependencies: ["IsletCore"]),

        // The app.
        .executableTarget(
            name: "Islet",
            dependencies: ["IsletCore", "IsletUI", "IsletModules"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),

        // The `islet` command-line client.
        .executableTarget(name: "IsletCLI", dependencies: ["IsletCore"]),

        .testTarget(name: "IsletCoreTests", dependencies: ["IsletCore"]),
        .testTarget(name: "IsletUITests", dependencies: ["IsletUI"]),
    ]
)
