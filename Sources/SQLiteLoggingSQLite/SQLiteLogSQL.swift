import Foundation
import StructuredQueriesSQLite

package enum SQLiteLogSQL {
    package static func buildQuery(
        _ query: SQLiteLogQuery,
        ids: [Int64]? = nil
    ) -> SelectOf<SQLiteLogRecord> {
        var statement = SQLiteLogRecord.all

        if let ids, !ids.isEmpty {
            statement = statement.where { $0.id.in(ids) }
        }
        if let from = query.from {
            statement = statement.where { $0.timestamp >= from }
        }
        if let to = query.to {
            statement = statement.where { $0.timestamp <= to }
        }
        if let levels = query.levels, !levels.isEmpty {
            statement = statement.where { $0.level.in(levels) }
        }
        if let label = query.label {
            statement = statement.where { $0.label.collate(.nocase) == label }
        }
        if let tag = query.tag {
            statement = statement.where { $0.tag == tag }
        }
        if let appName = query.appName {
            statement = statement.where { $0.appName == appName }
        }
        if let messageSearch = normalizedSearch(query.messageSearch) {
            statement = statement.where {
                $0.message.collate(.nocase).like("%\(messageSearch)%", escape: "!")
            }
        }

        var ordered = statement.order { ($0.timestamp.desc(), $0.id.desc()) }
        if let limit = query.limit {
            ordered = ordered.limit(limit, offset: query.offset)
        } else if let offset = query.offset {
            ordered = ordered.limit(-1, offset: offset)
        }

        return ordered
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
}
