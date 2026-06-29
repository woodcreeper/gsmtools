// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GSMTools",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GSMTools", targets: ["GSMTools"]),
        .library(name: "GSMToolsCore", targets: ["GSMToolsCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "7.0.0"))
    ],
    targets: [
        .target(
            name: "GSMToolsCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/GSMToolsCore"
        ),
        .executableTarget(
            name: "GSMTools",
            dependencies: ["GSMToolsCore"],
            path: "Sources/GSMTools",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GSMToolsCoreTests",
            dependencies: ["GSMToolsCore"],
            path: "Tests/GSMToolsCoreTests"
        )
    ]
)
