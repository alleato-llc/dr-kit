// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "dr-kit",
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "DRKit", targets: ["DRKit"]),
    ],
    dependencies: [
        .package(path: "../libav-kit"),
        .package(url: "git@github.com:alleato-llc/tint.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "DRKit",
            dependencies: [
                .product(name: "LibAVKit", package: "libav-kit"),
            ],
            path: "Sources/DRKit"
        ),
        .executableTarget(
            name: "dr",
            dependencies: [
                "DRKit",
                .product(name: "Tint", package: "tint"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/dr"
        ),
        .testTarget(
            name: "DRKitTests",
            dependencies: [
                "DRKit",
                .product(name: "LibAVKit", package: "libav-kit"),
            ]
        ),
    ]
)
