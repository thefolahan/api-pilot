// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "APIPilot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "APIPilotKit", targets: ["APIPilotKit"]),
        .executable(name: "APIPilot", targets: ["APIPilot"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(
            name: "APIPilotKit",
            dependencies: ["Yams"],
            path: "Sources/APIPilotKit"
        ),
        .executableTarget(
            name: "APIPilot",
            dependencies: ["APIPilotKit"],
            path: "Sources/APIPilot"
        ),
        .testTarget(
            name: "APIPilotTests",
            dependencies: ["APIPilot", "APIPilotKit"],
            path: "Tests/APIPilotTests"
        )
    ]
)
