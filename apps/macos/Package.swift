// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Turnshare",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Turnshare", targets: ["Turnshare"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Turnshare",
            dependencies: ["SessionCore", "ProviderClaude", "ProviderCodex", "ProviderOpenCode", "PublisherGist", "HotKey"],
            resources: [.process("Resources")]
        ),
        .target(name: "SessionCore"),
        .target(name: "ProviderClaude", dependencies: ["SessionCore"]),
        .target(name: "ProviderCodex", dependencies: ["SessionCore"]),
        .target(name: "ProviderOpenCode", dependencies: ["SessionCore"]),
        .target(name: "PublisherGist", dependencies: ["SessionCore"]),

        // Tests
        .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore"]),
        .testTarget(name: "ProviderClaudeTests", dependencies: ["ProviderClaude", "SessionCore"]),
        .testTarget(name: "ProviderCodexTests", dependencies: ["ProviderCodex", "SessionCore"]),
        .testTarget(name: "ProviderOpenCodeTests", dependencies: ["ProviderOpenCode", "SessionCore"]),
        .testTarget(name: "PublisherGistTests", dependencies: ["PublisherGist", "SessionCore"]),
        .testTarget(name: "TurnshareTests", dependencies: ["SessionCore", "ProviderClaude", "Turnshare", "HotKey"]),
    ]
)
