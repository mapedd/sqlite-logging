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

@Test func inMemoryQueryFiltersAndOrdering() async throws {
    let manager = sharedManager()
    let label = "FilterLabel-\(UUID().uuidString)"
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    await manager.record(
        timestamp: base,
        level: .info,
        message: "alpha 100% \(label)",
        metadata: ["user": "bob"],
        label: label,
        line: 10
    )
    await manager.record(
        timestamp: base.addingTimeInterval(5),
        level: .error,
        message: "beta \(label)",
        label: label,
        line: 20
    )
    await manager.record(
        timestamp: base.addingTimeInterval(10),
        level: .debug,
        message: "gamma \(label)",
        label: label,
        line: 30
    )

    await manager.flush()

    let all = try await manager.query(LogQuery(label: label))
    #expect(all.count == 3)

    let ordered = try await manager.query(LogQuery(label: label, limit: 2))
    #expect(ordered.map(\.message) == ["gamma \(label)", "beta \(label)"])

    let offset = try await manager.query(LogQuery(label: label, limit: 2, offset: 1))
    #expect(offset.map(\.message) == ["beta \(label)", "alpha 100% \(label)"])

    let windowed = try await manager.query(
        LogQuery(
            from: base.addingTimeInterval(2),
            to: base.addingTimeInterval(8),
            label: label
        )
    )
    #expect(windowed.count == 1)
    #expect(windowed.first?.message == "beta \(label)")

    let levelFiltered = try await manager.query(
        LogQuery(levels: [.error, .debug], label: label)
    )
    #expect(levelFiltered.count == 2)
    #expect(
        levelFiltered.allSatisfy {
            $0.level == Logger.Level.error || $0.level == Logger.Level.debug
        }
    )

    let percentSearch = try await manager.query(
        LogQuery(label: label, messageSearch: "%")
    )
    #expect(percentSearch.count == 1)
    #expect(percentSearch.first?.message.contains("100%") == true)

    let blankSearch = try await manager.query(
        LogQuery(label: label, messageSearch: "   ")
    )
    #expect(blankSearch.count == 3)

    let tagMatches = try await manager.query(LogQuery(tag: label))
    #expect(tagMatches.count == 3)
    #expect(tagMatches.allSatisfy { $0.tag == label })

    let wrongApp = try await manager.query(
        LogQuery(label: label, appName: "OtherApp")
    )
    #expect(wrongApp.isEmpty)

    let alphaRecord = try #require(all.first { $0.message.hasPrefix("alpha") })
    #expect(alphaRecord.metadataJSON.contains("\"user\""))
    #expect(alphaRecord.line == 10)
}

@Test func queryOrderingNewestAndOldestFirst() async throws {
    let manager = sharedManager()
    let label = "SortOrder-\(UUID().uuidString)"
    let base = Date(timeIntervalSince1970: 1_700_000_100)

    await manager.record(
        timestamp: base,
        level: .info,
        message: "first \(label)",
        label: label
    )
    await manager.record(
        timestamp: base,
        level: .info,
        message: "second \(label)",
        label: label
    )
    await manager.record(
        timestamp: base.addingTimeInterval(10),
        level: .info,
        message: "third \(label)",
        label: label
    )

    await manager.flush()

    let newest = try await manager.query(
        LogQuery(label: label, order: .newestFirst)
    )
    #expect(
        newest.map(\.message) == [
            "third \(label)",
            "second \(label)",
            "first \(label)",
        ]
    )

    let oldest = try await manager.query(
        LogQuery(label: label, order: .oldestFirst)
    )
    #expect(
        oldest.map(\.message) == [
            "first \(label)",
            "second \(label)",
            "third \(label)",
        ]
    )
}

@Test func logStreamEmitsInInsertOrder() async throws {
    let manager = sharedManager()
    let label = "StreamOrder-\(UUID().uuidString)"
    let stream = await manager.logStream(query: LogQuery(label: label))
    let base = Date()
    var iterator = stream.makeAsyncIterator()
    let expectedMessages = [
        "first \(label)",
        "second \(label)",
        "third \(label)",
    ]

    await manager.record(
        timestamp: base,
        level: .info,
        message: expectedMessages[0],
        label: label
    )
    let first = try #require(await iterator.next())
    #expect(first.message == expectedMessages[0])
    try await assertOrdering(
        manager: manager,
        label: label,
        expected: Array(expectedMessages.prefix(1))
    )

    await manager.record(
        timestamp: base.addingTimeInterval(1),
        level: .info,
        message: expectedMessages[1],
        label: label
    )
    let second = try #require(await iterator.next())
    #expect(second.message == expectedMessages[1])
    try await assertOrdering(
        manager: manager,
        label: label,
        expected: Array(expectedMessages.prefix(2))
    )

    await manager.record(
        timestamp: base.addingTimeInterval(2),
        level: .info,
        message: expectedMessages[2],
        label: label
    )
    let third = try #require(await iterator.next())
    #expect(third.message == expectedMessages[2])
    try await assertOrdering(
        manager: manager,
        label: label,
        expected: expectedMessages
    )
}

private func assertOrdering(
    manager: SQLiteLogManager,
    label: String,
    expected: [String]
) async throws {
    let oldest = try await manager.query(
        LogQuery(label: label, order: .oldestFirst)
    )
    #expect(oldest.map(\.message) == expected)

    let newest = try await manager.query(
        LogQuery(label: label, order: .newestFirst)
    )
    #expect(newest.map(\.message) == expected.reversed())
}

private func sharedManager() -> SQLiteLogManager {
    TestLogging.sharedManager
}

private enum TestLogging {
    static let sharedManager: SQLiteLogManager = {
        let configuration = SQLiteLoggingConfiguration(
            appName: "SQLiteLoggingTests",
            queueDepth: 64,
            dropPolicy: nil,
            database: .inMemory()
        )

        return try! SQLiteLoggingSystem.bootstrap(configuration: configuration)
    }()
}
