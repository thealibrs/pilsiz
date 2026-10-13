// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pilsiz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Pilsiz", path: "Sources/Pilsiz")
    ]
)
