import Foundation
import Logging
import Testing
@testable import SQLiteLogging

@Test func metadataJSONEncoding() async throws {
    let metadata: Logger.Metadata = [
        "user": "alice",
        "attempts": .stringConvertible(3),
        "flags": .array(["a", "b"]),
        "nested": .dictionary(["enabled": "true"]),
    ]
    let json = MetadataJSONEncoder.encode(metadata)
    #expect(json.contains("\"user\""))
    #expect(json.contains("\"attempts\""))
    #expect(json.contains("\"nested\""))
}

@Test func sqliteWriteRead() async throws {
    let manager = sharedManager()
    let label = "TestLabel-\(UUID().uuidString)"
    let logger = Logger(label: label)
    logger.info("hello sqlite", metadata: ["user": "alice"])

    try await Task.sleep(for: .milliseconds(50))
    await manager.flush()

    let records = try await manager.query(LogQuery(label: label, limit: 10))
    #expect(!records.isEmpty)
    let record = try #require(records.first)
    #expect(record.label == label)
    #expect(record.tag == label)
    #expect(record.appName == "SQLiteLoggingTests")
    #expect(record.message.contains("hello sqlite"))

    await manager.flush()
}

@Test func messageSearchFilters() async throws {
    let manager = sharedManager()
    let label = "SearchLabel-\(UUID().uuidString)"
    let logger = Logger(label: label)
    logger.info("alpha message \(label)")
    logger.info("beta message \(label)")

    try await Task.sleep(for: .milliseconds(50))
    await manager.flush()

    let records = try await manager.query(
        LogQuery(label: label, messageSearch: "beta", limit: 10)
    )
    #expect(records.count == 1)
    #expect(records.first?.message.contains("beta") == true)

    await manager.flush()
}

private func sharedManager() -> SQLiteLogManager {
    TestLogging.sharedManager
}

private enum TestLogging {
    static let sharedManager: SQLiteLogManager = {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sqlite-logging-tests.sqlite")

        let configuration = SQLiteLoggingConfiguration(
            appName: "SQLiteLoggingTests",
            queueDepth: 64,
            dropPolicy: nil,
            database: SQLiteDatabaseConfiguration(storage: .file(databaseURL))
        )

        return try! SQLiteLoggingSystem.bootstrap(configuration: configuration)
    }()
}
