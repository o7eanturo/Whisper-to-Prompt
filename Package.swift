// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceCodexAssistant",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceCodexCore", targets: ["VoiceCodexCore"]),
        .executable(name: "voice-codex", targets: ["VoiceCodexMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0")
    ],
    targets: [
        .target(name: "VoiceCodexCore"),
        .executableTarget(
            name: "VoiceCodexMac",
            dependencies: [
                "VoiceCodexCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
