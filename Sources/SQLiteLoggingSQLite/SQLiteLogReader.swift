import Foundation
import GRDB
import SQLiteData

package actor SQLiteLogReader {
    private let database: DatabaseQueue

    package init(databaseURL: URL) throws {
        var configuration = Configuration()
        configuration.readonly = true
        self.database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
    }

    package func query(_ query: SQLiteLogQuery) async throws -> [SQLiteLogRecord] {
        let (sql, arguments) = SQLiteLogSQL.buildQuery(query)
        return try await database.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return SQLiteLogSQL.mapRows(rows)
        }
    }
}
