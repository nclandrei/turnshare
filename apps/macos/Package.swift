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
            dependencies: ["SessionCore", "ProviderClaude", "PublisherGist", "HotKey"]
        ),
        .target(name: "SessionCore"),
        .target(name: "ProviderClaude", dependencies: ["SessionCore"]),
        .target(name: "PublisherGist", dependencies: ["SessionCore"]),
    ]
)
