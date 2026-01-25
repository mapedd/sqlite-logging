// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SQLiteLogging",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "SQLiteLogging",
            targets: ["SQLiteLogging"]
        ),
        .library(
            name: "SQLiteLoggingViewer",
            targets: ["SQLiteLoggingViewer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
        .package(url: "https://github.com/pointfreeco/sqlite-data.git", from: "1.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.28.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.9.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SQLiteLogging",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "SQLiteLoggingSQLite",
            ]
        ),
        .target(
            name: "SQLiteLoggingSQLite",
            dependencies: [
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
            ]
        ),
        .target(
            name: "SQLiteLoggingViewer",
            dependencies: [
                "SQLiteLogging",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ]
        ),
        .testTarget(
            name: "SQLiteLoggingTests",
            dependencies: ["SQLiteLogging"]
        ),
    ]
)
