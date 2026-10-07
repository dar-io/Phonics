// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StorySoundsCore",
    platforms: [.tvOS(.v17), .macOS(.v13)],
    products: [.library(name: "StorySoundsCore", targets: ["StorySoundsCore"])],
    targets: [
        .target(name: "StorySoundsCore", resources: [.process("Resources")]),
        .testTarget(name: "StorySoundsCoreTests", dependencies: ["StorySoundsCore"]),
    ]
)
