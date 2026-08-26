// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimeTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TimeTracker",
            path: "Sources/TimeTracker"
        )
    ]
)
