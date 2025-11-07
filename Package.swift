// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Clipper",
            targets: ["ClipperApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ClipperApp",
            path: "Sources/ClipperApp"
        )
    ]
)
