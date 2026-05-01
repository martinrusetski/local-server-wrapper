// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalServerWrapper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "LocalServerWrapper",
            targets: ["LocalServerWrapper"])
    ],
    targets: [
        .executableTarget(
            name: "LocalServerWrapper",
            path: "LocalServerWrapper",
            resources: [
                .copy("../ServerAppBundle.entitlements")
            ]
        ),
        .testTarget(
            name: "LocalServerWrapperTests",
            dependencies: ["LocalServerWrapper"],
            path: "Tests"
        )
    ]
)
