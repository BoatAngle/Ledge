// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ledge", targets: ["Ledge"]),
        // Named `ledge-cli` rather than `ledge`: macOS filesystems are
        // case-insensitive, so a product called `ledge` collides with the
        // `Ledge` app target's build directory. `make app` installs the binary
        // into the bundle as plain `ledge`.
        .executable(name: "ledge-cli", targets: ["LedgeCLI"]),
        .library(name: "LedgeCore", targets: ["LedgeCore"]),
    ],
    targets: [
        // Pure model + engine. No AppKit, no SwiftUI — this is what the CLI
        // links against too, so it must stay UI-free and portable.
        .target(name: "LedgeCore"),

        // The island itself: window, shape, morph, presentations.
        .target(name: "LedgeUI", dependencies: ["LedgeCore"]),

        // Built-in providers that feed system state into the engine.
        .target(name: "LedgeModules", dependencies: ["LedgeCore"]),

        // The app.
        .executableTarget(
            name: "Ledge",
            dependencies: ["LedgeCore", "LedgeUI", "LedgeModules"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),

        // The `ledge` command-line client.
        .executableTarget(name: "LedgeCLI", dependencies: ["LedgeCore"]),

        .testTarget(name: "LedgeCoreTests", dependencies: ["LedgeCore"]),
        .testTarget(name: "LedgeUITests", dependencies: ["LedgeUI"]),
        .testTarget(name: "LedgeModulesTests", dependencies: ["LedgeModules"]),
    ]
)
