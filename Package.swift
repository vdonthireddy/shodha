// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shodha",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Shodha", targets: ["Shodha"])
    ],
    targets: [
        .executableTarget(
            name: "Shodha",
            path: "Sources"
        )
    ]
)
