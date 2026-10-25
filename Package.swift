// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Encore",
    defaultLocalization: "fr",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Encore", targets: ["Encore"])],
    targets: [
        .target(name: "EncoreCore", resources: [.process("Resources")]),
        .executableTarget(name: "Encore", dependencies: ["EncoreCore"], resources: [.copy("Resources/Sounds")]),
        .testTarget(name: "EncoreCoreTests", dependencies: ["EncoreCore"]),
        .testTarget(name: "EncoreAppTests", dependencies: ["Encore"])
    ]
)
