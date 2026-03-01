// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "clings",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "clings", targets: ["ClingsCLI"]),
        .library(name: "ClingsCore", targets: ["ClingsCore"])
    ],
    dependencies: [
        // CLI framework (Apple's official)
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        // SQLite for local database (sessions, cache, stats)
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClingsCLI",
            dependencies: [
                "ClingsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "ClingsCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "ClingsCoreTests",
            dependencies: ["ClingsCore"]
        ),
        .testTarget(
            name: "ClingsCLITests",
            dependencies: [
                "ClingsCLI",
                "ClingsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
