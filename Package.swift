// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "APIPilot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "APIPilot",
            dependencies: ["Yams"],
            path: "Sources/APIPilot"
        ),
        .testTarget(
            name: "APIPilotTests",
            dependencies: ["APIPilot"],
            path: "Tests/APIPilotTests"
        )
    ]
)
