// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Encore",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Encore", targets: ["Encore"])],
    targets: [
        .target(name: "EncoreCore"),
        .executableTarget(name: "Encore", dependencies: ["EncoreCore"]),
        .testTarget(name: "EncoreCoreTests", dependencies: ["EncoreCore"]),
        .testTarget(name: "EncoreAppTests", dependencies: ["Encore"])
    ]
)
