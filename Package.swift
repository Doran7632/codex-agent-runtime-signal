// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexAgentRuntimeSignal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexAgentRuntimeSignal", targets: ["CodexAgentRuntimeSignal"]),
        .executable(name: "codex-agent-runtime-signal", targets: ["CodexAgentRuntimeSignalCLI"]),
        .executable(name: "codex-agent-runtime-signal-checks", targets: ["CodexAgentRuntimeSignalChecks"]),
        .executable(name: "codex-agent-runtime-signal-icon-preview", targets: ["CodexAgentRuntimeSignalIconPreview"]),
        .library(name: "CodexAgentRuntimeSignalCore", targets: ["CodexAgentRuntimeSignalCore"]),
        .library(name: "CodexAgentRuntimeSignalUI", targets: ["CodexAgentRuntimeSignalUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3")
    ],
    targets: [
        .target(name: "CodexAgentRuntimeSignalCore"),
        .target(
            name: "CodexAgentRuntimeSignalUI",
            dependencies: ["CodexAgentRuntimeSignalCore"]
        ),
        .executableTarget(
            name: "CodexAgentRuntimeSignal",
            dependencies: [
                "CodexAgentRuntimeSignalCore",
                "CodexAgentRuntimeSignalUI",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "CodexAgentRuntimeSignalCLI",
            dependencies: ["CodexAgentRuntimeSignalCore"]
        ),
        .executableTarget(
            name: "CodexAgentRuntimeSignalChecks",
            dependencies: ["CodexAgentRuntimeSignalCore"]
        ),
        .executableTarget(
            name: "CodexAgentRuntimeSignalIconPreview",
            dependencies: [
                "CodexAgentRuntimeSignalCore",
                "CodexAgentRuntimeSignalUI"
            ]
        ),
        .testTarget(
            name: "CodexAgentRuntimeSignalCoreTests",
            dependencies: [
                "CodexAgentRuntimeSignal",
                "CodexAgentRuntimeSignalCore",
                "CodexAgentRuntimeSignalUI"
            ]
        )
    ]
)
