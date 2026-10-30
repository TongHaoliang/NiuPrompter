// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartTeleprompterProbe",
    // The installed SwiftPM manifest API predates the named .v26 constants.
    // Version strings keep the same 26.0 deployment floor on that toolchain.
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "TeleprompterCore", targets: ["TeleprompterCore"]),
        .library(name: "TeleprompterSpeech", targets: ["TeleprompterSpeech"]),
        .library(name: "TeleprompterPresentation", targets: ["TeleprompterPresentation"]),
        .executable(name: "SmartTeleprompterMac", targets: ["SmartTeleprompterMac"]),
        .executable(name: "TeleprompterChecks", targets: ["TeleprompterChecks"]),
    ],
    targets: [
        .target(name: "TeleprompterCore"),
        .target(name: "TeleprompterSpeech", dependencies: ["TeleprompterCore"]),
        .target(name: "TeleprompterPresentation", dependencies: ["TeleprompterCore", "TeleprompterSpeech"]),
        .executableTarget(
            name: "SmartTeleprompterMac",
            dependencies: ["TeleprompterCore", "TeleprompterSpeech", "TeleprompterPresentation"],
            path: "Sources/SmartTeleprompterMac"
        ),
        .executableTarget(
            name: "TeleprompterChecks",
            dependencies: ["TeleprompterCore", "TeleprompterSpeech", "TeleprompterPresentation"],
            path: "Tests/TeleprompterCoreTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
