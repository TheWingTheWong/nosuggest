// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nosuggest",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "nosuggest", targets: ["nosuggest"]),
        .library(name: "NoSuggestCore", targets: ["NoSuggestCore"]),
    ],
    targets: [
        .target(name: "NoSuggestCore"),
        .executableTarget(
            name: "nosuggest",
            dependencies: ["NoSuggestCore"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(name: "NoSuggestCoreTests", dependencies: ["NoSuggestCore"]),
    ]
)
