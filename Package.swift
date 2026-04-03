// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenDisplay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenDisplay",
            path: "OpenDisplay"
        )
    ]
)
