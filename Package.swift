// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimeWaster",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TimeWaster", targets: ["TimeWaster"])
    ],
    targets: [
        .executableTarget(
            name: "TimeWaster",
            path: "Sources/TimeWaster"
        )
    ]
)
