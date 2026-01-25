import Foundation
import Logging
import SQLiteLoggingSQLite

public struct LogRecord: Sendable, Equatable {
    public let id: Int64
    public let timestamp: Date
    public let level: Logger.Level
    public let label: String
    public let tag: String
    public let appName: String
    public let message: String
    public let metadataJSON: String
    public let source: String
    public let file: String
    public let function: String
    public let line: UInt
}

public struct LogQuery: Sendable {
    public var from: Date?
    public var to: Date?
    public var levels: [Logger.Level]?
    public var label: String?
    public var tag: String?
    public var appName: String?
    public var messageSearch: String?
    public var limit: Int?
    public var offset: Int?

    public init(
        from: Date? = nil,
        to: Date? = nil,
        levels: [Logger.Level]? = nil,
        label: String? = nil,
        tag: String? = nil,
        appName: String? = nil,
        messageSearch: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.from = from
        self.to = to
        self.levels = levels
        self.label = label
        self.tag = tag
        self.appName = appName
        self.messageSearch = messageSearch
        self.limit = limit
        self.offset = offset
    }
}

public struct SQLiteLogManager: Sendable {
    private let dispatcher: LogDispatcher
    private let store: SQLiteLogStore
    public let databaseStorage: SQLiteDatabaseStorage
    public let appName: String

    init(
        dispatcher: LogDispatcher,
        store: SQLiteLogStore,
        databaseStorage: SQLiteDatabaseStorage,
        appName: String
    ) {
        self.dispatcher = dispatcher
        self.store = store
        self.databaseStorage = databaseStorage
        self.appName = appName
    }

    public var databaseURL: URL? {
        if case let .file(url) = databaseStorage {
            return url
        }
        return nil
    }

    public func flush() async {
        await dispatcher.flush()
    }

    public func record(
        timestamp: Date = Date(),
        level: Logger.Level,
        message: String,
        metadata: Logger.Metadata = [:],
        label: String,
        source: String = "SQLiteLogging",
        file: String = "",
        function: String = "",
        line: UInt = 0
    ) async {
        let metadataJSON = MetadataJSONEncoder.encode(metadata)
        let event = LogEvent(
            timestamp: timestamp,
            level: level,
            message: message,
            label: label,
            tag: label,
            metadata: metadata,
            metadataJSON: metadataJSON,
            appName: appName,
            source: source,
            file: file,
            function: function,
            line: line
        )
        await dispatcher.enqueue(event)
    }

    public func shutdown() async {
        await dispatcher.shutdown()
    }

    public func service() -> SQLiteLoggingService {
        SQLiteLoggingService(dispatcher: dispatcher)
    }

    public func logStream(query: LogQuery? = nil) async -> AsyncStream<LogRecord> {
        let streamQuery = sqliteQuery(query, includePagination: false)
        let stream = await dispatcher.stream()
        return AsyncStream { continuation in
            let task = Task {
                for await record in stream {
                    do {
                        let matches = try await store.query(streamQuery, matchingIDs: [record.id])
                        for match in matches {
                            continuation.yield(LogRecord(match))
                        }
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func query(_ query: LogQuery) async throws -> [LogRecord] {
        let input = sqliteQuery(query, includePagination: true)
        let records = try await store.query(input)
        return records.map { LogRecord($0) }
    }

    public func databaseSizeBytes() async throws -> Int64? {
        return try await store.databaseSizeBytes()
    }
}

public protocol Service: Sendable {
    func run() async throws
    func shutdown() async
}

public struct SQLiteLoggingService: Service, Sendable {
    private let dispatcher: LogDispatcher

    init(dispatcher: LogDispatcher) {
        self.dispatcher = dispatcher
    }

    public func run() async throws {
        await dispatcher.waitForShutdown()
    }

    public func shutdown() async {
        await dispatcher.shutdown()
    }
}

extension LogRecord {
    init(_ record: SQLiteLogRecord) {
        self.id = record.id
        self.timestamp = record.timestamp
        self.level = Logger.Level(rawValue: record.level) ?? .info
        self.label = record.label
        self.tag = record.tag
        self.appName = record.appName
        self.message = record.message
        self.metadataJSON = record.metadataJSON
        self.source = record.source
        self.file = record.file
        self.function = record.function
        self.line = UInt(clamping: record.line)
    }
}

extension SQLiteLogQuery {
    init(_ query: LogQuery, includePagination: Bool) {
        self.init(
            from: query.from,
            to: query.to,
            levels: query.levels?.map { $0.rawValue },
            label: query.label,
            tag: query.tag,
            appName: query.appName,
            messageSearch: query.messageSearch,
            limit: includePagination ? query.limit : nil,
            offset: includePagination ? query.offset : nil
        )
    }
}

private func sqliteQuery(
    _ query: LogQuery?,
    includePagination: Bool
) -> SQLiteLogQuery {
    guard let query else {
        return SQLiteLogQuery(
            from: nil,
            to: nil,
            levels: nil,
            label: nil,
            tag: nil,
            appName: nil,
            messageSearch: nil,
            limit: nil,
            offset: nil
        )
    }
    return SQLiteLogQuery(query, includePagination: includePagination)
}
