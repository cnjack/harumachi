// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MioCompanion",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MioCompanion", targets: ["MioApp"])],
    targets: [
        .target(name: "MioCore"),
        .executableTarget(name: "MioApp", dependencies: ["MioCore"],
                          resources: [.copy("Resources")]),
        .executableTarget(name: "MioCubismBake", dependencies: ["MioCore"]),
        .testTarget(name: "MioCoreTests", dependencies: ["MioCore"])
    ],
    swiftLanguageModes: [.v5]
)
