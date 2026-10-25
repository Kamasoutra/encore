// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Encore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Encore", targets: ["Encore"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "EncoreCore", resources: [.process("Resources")]),
        .executableTarget(name: "Encore", dependencies: ["EncoreCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources/Sounds")]),
        .testTarget(name: "EncoreCoreTests", dependencies: ["EncoreCore"]),
        .testTarget(name: "EncoreAppTests", dependencies: ["Encore"])
    ]
)
