import Foundation
import GRDB

package enum SQLiteLogSQL {
    package static func buildQuery(
        _ query: SQLiteLogQuery
    ) -> (String, StatementArguments) {
        var sql = "SELECT * FROM logs"
        var conditions: [String] = []
        var arguments = StatementArguments()
        let formatter = makeFormatter()

        if let from = query.from {
            conditions.append("timestamp >= ?")
            _ = arguments.append(contentsOf: StatementArguments([formatter.string(from: from)]))
        }
        if let to = query.to {
            conditions.append("timestamp <= ?")
            _ = arguments.append(contentsOf: StatementArguments([formatter.string(from: to)]))
        }
        if let levels = query.levels, !levels.isEmpty {
            let placeholders = Array(repeating: "?", count: levels.count).joined(separator: ", ")
            conditions.append("level IN (\(placeholders))")
            _ = arguments.append(contentsOf: StatementArguments(levels))
        }
        if let label = query.label {
            conditions.append("label = ?")
            _ = arguments.append(contentsOf: StatementArguments([label]))
        }
        if let tag = query.tag {
            conditions.append("tag = ?")
            _ = arguments.append(contentsOf: StatementArguments([tag]))
        }
        if let appName = query.appName {
            conditions.append("app = ?")
            _ = arguments.append(contentsOf: StatementArguments([appName]))
        }
        if let messageSearch = normalizedSearch(query.messageSearch) {
            conditions.append("message LIKE ? ESCAPE '!'")
            _ = arguments.append(contentsOf: StatementArguments(["%\(messageSearch)%"]))
        }

        if !conditions.isEmpty {
            sql += " WHERE \(conditions.joined(separator: " AND "))"
        }
        sql += " ORDER BY timestamp DESC"

        if let limit = query.limit {
            sql += " LIMIT \(limit)"
        }
        if let offset = query.offset {
            if query.limit == nil {
                sql += " LIMIT -1"
            }
            sql += " OFFSET \(offset)"
        }

        return (sql, arguments)
    }

    package static func mapRows(
        _ rows: [Row]
    ) -> [SQLiteLogRecord] {
        let formatter = makeFormatter()
        return rows.map { row in
            let timestampString: String = row["timestamp"]
            let timestamp = formatter.date(from: timestampString) ?? Date(timeIntervalSince1970: 0)
            let line: Int64 = row["line"]
            return SQLiteLogRecord(
                id: row["id"],
                timestamp: timestamp,
                level: row["level"],
                label: row["label"],
                tag: row["tag"],
                appName: row["app"],
                message: row["message"],
                metadataJSON: row["metadata_json"],
                source: row["source"],
                file: row["file"],
                function: row["function"],
                line: UInt(line)
            )
        }
    }

    private static func normalizedSearch(_ input: String?) -> String? {
        guard let input else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "!", with: "!!")
            .replacingOccurrences(of: "%", with: "!%")
            .replacingOccurrences(of: "_", with: "!_")
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
