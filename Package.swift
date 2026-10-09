// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "APIPilot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "APIPilotKit", targets: ["APIPilotKit"]),
        .executable(name: "apipilot", targets: ["apipilot"]),
        .executable(name: "APIPilotApp", targets: ["APIPilotApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "APIPilotKit",
            dependencies: ["Yams"],
            path: "Sources/APIPilotKit"
        ),
        .executableTarget(
            name: "apipilot",
            dependencies: ["APIPilotKit", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources/APIPilotCLI"
        ),
        .executableTarget(
            name: "APIPilotApp",
            dependencies: ["APIPilotKit"],
            path: "Sources/APIPilotApp"
        ),
        .testTarget(
            name: "APIPilotTests",
            dependencies: ["APIPilotApp", "APIPilotKit"],
            path: "Tests/APIPilotTests"
        )
    ]
)
