import Foundation
import GRDB
import SQLiteData
import StructuredQueriesSQLite

package actor SQLiteLogStore {
    package let storage: SQLiteLogStoreStorage
    private let databasePath: String
    private let database: DatabaseQueue

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
        let database = try DatabaseQueue(path: databasePath)
        try Self.migrate(database)
        if let maxDatabaseBytes {
            try Self.applyMaxDatabaseSize(maxDatabaseBytes, database: database)
        }
        self.storage = storage
        self.databasePath = databasePath
        self.database = database
    }

    package func append(_ entry: SQLiteLogEntry) -> SQLiteLogRecord? {
        do {
            return try database.write { db in
                try SQLiteLogRecord
                    .insert {
                        (
                            $0.timestamp,
                            $0.level,
                            $0.label,
                            $0.tag,
                            $0.appName,
                            $0.message,
                            $0.metadataJSON,
                            $0.source,
                            $0.file,
                            $0.function,
                            $0.line
                        )
                    } values: {
                        (
                            entry.timestamp,
                            entry.level,
                            entry.label,
                            entry.tag,
                            entry.appName,
                            entry.message,
                            entry.metadataJSON,
                            entry.source,
                            entry.file,
                            entry.function,
                            entry.line
                        )
                    }
                    .execute(db)
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
                    line: entry.line
                )
            }
        } catch {
            // Drop on write error to avoid blocking the pipeline.
            return nil
        }
    }

    package func flush() {}

    package func query(_ query: SQLiteLogQuery) async throws -> [SQLiteLogRecord] {
        let statement = SQLiteLogSQL.buildQuery(query)
        return try await database.read { db in
            try statement.fetchAll(db)
        }
    }

    package func query(
        _ query: SQLiteLogQuery,
        matchingIDs ids: [Int64]
    ) async throws -> [SQLiteLogRecord] {
        guard !ids.isEmpty else { return [] }
        let statement = SQLiteLogSQL.buildQuery(query, ids: ids)
        return try await database.read { db in
            try statement.fetchAll(db)
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
            try db.create(table: "logs", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("timestamp", .text).notNull()
                table.column("level", .text).notNull()
                table.column("label", .text).notNull()
                table.column("tag", .text).notNull()
                table.column("app", .text).notNull()
                table.column("message", .text).notNull()
                table.column("metadata_json", .text).notNull()
                table.column("source", .text).notNull()
                table.column("file", .text).notNull()
                table.column("function", .text).notNull()
                table.column("line", .integer).notNull()
            }
            try db.create(
                index: "logs_timestamp_idx",
                on: "logs",
                columns: ["timestamp"],
                ifNotExists: true
            )
            try db.create(
                index: "logs_level_idx",
                on: "logs",
                columns: ["level"],
                ifNotExists: true
            )
            try db.create(
                index: "logs_tag_idx",
                on: "logs",
                columns: ["tag"],
                ifNotExists: true
            )
            try db.create(
                index: "logs_label_idx",
                on: "logs",
                columns: ["label"],
                ifNotExists: true
            )
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
