import Foundation
import GRDB
import SQLiteData

package actor SQLiteLogStore {
    package let storage: SQLiteLogStoreStorage
    private let databasePath: String
    private let database: DatabaseQueue
    private let dateFormatter: ISO8601DateFormatter

    package init(
        storage: SQLiteLogStoreStorage,
        maxDatabaseBytes: Int64?
    ) throws {
        let databasePath: String
        switch storage {
        case .inMemory:
            databasePath = ":memory:"
        case .file(let url):
            databasePath = url.path
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let database = try DatabaseQueue(path: databasePath)
        try Self.migrate(database)
        if let maxDatabaseBytes {
            try Self.applyMaxDatabaseSize(maxDatabaseBytes, database: database)
        }
        self.storage = storage
        self.databasePath = databasePath
        self.database = database
        self.dateFormatter = formatter
    }

    package func append(_ entry: SQLiteLogEntry) -> SQLiteLogRecord? {
        do {
            let timestamp = dateFormatter.string(from: entry.timestamp)
            return try database.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO logs (
                      timestamp, level, label, tag, app, message, metadata_json,
                      source, file, function, line
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        timestamp,
                        entry.level,
                        entry.label,
                        entry.tag,
                        entry.appName,
                        entry.message,
                        entry.metadataJSON,
                        entry.source,
                        entry.file,
                        entry.function,
                        entry.line,
                    ]
                )
                return SQLiteLogRecord(
                    id: db.lastInsertedRowID,
                    timestamp: entry.timestamp,
                    level: entry.level,
                    label: entry.label,
                    tag: entry.tag,
                    appName: entry.appName,
                    message: entry.message,
                    metadataJSON: entry.metadataJSON,
                    source: entry.source,
                    file: entry.file,
                    function: entry.function,
                    line: UInt(entry.line)
                )
            }
        } catch {
            // Drop on write error to avoid blocking the pipeline.
            return nil
        }
    }

    package func flush() {}

    package func query(_ query: SQLiteLogQuery) async throws -> [SQLiteLogRecord] {
        let (sql, arguments) = SQLiteLogSQL.buildQuery(query)
        return try await database.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return SQLiteLogSQL.mapRows(rows)
        }
    }

    package func query(
        _ query: SQLiteLogQuery,
        matchingIDs ids: [Int64]
    ) async throws -> [SQLiteLogRecord] {
        guard !ids.isEmpty else { return [] }
        let (sql, arguments) = SQLiteLogSQL.buildQuery(query, ids: ids)
        return try await database.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return SQLiteLogSQL.mapRows(rows)
        }
    }

    package func databaseSizeBytes() throws -> Int64? {
        if databasePath == ":memory:" {
            return nil
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: databasePath)
        if let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    private static func migrate(_ database: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create-logs") { db in
            try db.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS logs (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  timestamp TEXT NOT NULL,
                  level TEXT NOT NULL,
                  label TEXT NOT NULL,
                  tag TEXT NOT NULL,
                  app TEXT NOT NULL,
                  message TEXT NOT NULL,
                  metadata_json TEXT NOT NULL,
                  source TEXT NOT NULL,
                  file TEXT NOT NULL,
                  function TEXT NOT NULL,
                  line INTEGER NOT NULL
                )
                """
            )
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS logs_timestamp_idx ON logs(timestamp)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS logs_level_idx ON logs(level)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS logs_tag_idx ON logs(tag)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS logs_label_idx ON logs(label)")
        }
        try migrator.migrate(database)
    }

    private static func applyMaxDatabaseSize(_ maxBytes: Int64, database: DatabaseQueue) throws {
        try database.write { db in
            let pageSize = try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 4096
            let maxPages = max(1, Int(maxBytes) / max(1, pageSize))
            try db.execute(sql: "PRAGMA max_page_count = \(maxPages)")
        }
    }
}
