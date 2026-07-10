// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexModelSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexModelSwitcher", targets: ["CodexModelSwitcher"]),
        .library(name: "CodexModelSwitcherCore", targets: ["CodexModelSwitcherCore"])
    ],
    targets: [
        .target(
            name: "CodexModelSwitcherCore",
            resources: [
                .copy("Resources/codex_9router_proxy.py")
            ]
        ),
        .executableTarget(
            name: "CodexModelSwitcher",
            dependencies: ["CodexModelSwitcherCore"]
        ),
        .testTarget(
            name: "CodexModelSwitcherTests",
            dependencies: ["CodexModelSwitcherCore"]
        )
    ]
)
