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
        .executableTarget(
            name: "maclink",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/maclink"
        ),
        .testTarget(
            name: "maclinkTests",
            dependencies: ["maclink"],
            path: "Tests/maclinkTests"
        )
    ]
)
