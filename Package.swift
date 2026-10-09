// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Specline",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .executableTarget(
            name: "Specline",
            dependencies: ["Yams"],
            path: "Sources/Specline"
        ),
        .testTarget(
            name: "SpeclineTests",
            dependencies: ["Specline"],
            path: "Tests/SpeclineTests"
        )
    ]
)
