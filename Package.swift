// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TVKumanda",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TVKumanda", path: "Sources/TVKumanda")
    ]
)
