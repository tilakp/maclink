// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "maclink",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(name: "MaclinkShared", path: "Sources/MaclinkShared"),
        .executableTarget(
            name: "maclink",
            dependencies: [
                "MaclinkShared",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/maclink"
        ),
        .executableTarget(
            name: "maclink-cli",
            dependencies: [
                "MaclinkShared",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/maclink-cli"
        ),
        .testTarget(
            name: "maclinkTests",
            dependencies: ["maclink", "MaclinkShared"],
            path: "Tests/maclinkTests"
        )
    ]
)
