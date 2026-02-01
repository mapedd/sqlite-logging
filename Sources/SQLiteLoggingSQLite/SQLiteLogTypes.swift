import Foundation
import StructuredQueriesSQLite

package struct SQLiteLogEntry: Sendable {
    package var uuid: String
    package var timestamp: Date
    package var level: String
    package var label: String
    package var tag: String
    package var appName: String
    package var message: String
    package var metadataJSON: String
    package var source: String
    package var file: String
    package var function: String
    package var line: Int64

    package init(
        uuid: String,
        timestamp: Date,
        level: String,
        label: String,
        tag: String,
        appName: String,
        message: String,
        metadataJSON: String,
        source: String,
        file: String,
        function: String,
        line: Int64
    ) {
        self.uuid = uuid
        self.timestamp = timestamp
        self.level = level
        self.label = label
        self.tag = tag
        self.appName = appName
        self.message = message
        self.metadataJSON = metadataJSON
        self.source = source
        self.file = file
        self.function = function
        self.line = line
    }
}

@Table("logs")
package struct SQLiteLogRecord: Sendable, Equatable {
    package var id: Int64
    @Column("uuid")
    package var uuid: String
    package var timestamp: Date
    package var level: String
    package var label: String
    package var tag: String
    @Column("app")
    package var appName: String
    package var message: String
    @Column("metadata_json")
    package var metadataJSON: String
    package var source: String
    package var file: String
    package var function: String
    package var line: Int64

    package init(
        id: Int64,
        uuid: String,
        timestamp: Date,
        level: String,
        label: String,
        tag: String,
        appName: String,
        message: String,
        metadataJSON: String,
        source: String,
        file: String,
        function: String,
        line: Int64
    ) {
        self.id = id
        self.uuid = uuid
        self.timestamp = timestamp
        self.level = level
        self.label = label
        self.tag = tag
        self.appName = appName
        self.message = message
        self.metadataJSON = metadataJSON
        self.source = source
        self.file = file
        self.function = function
        self.line = line
    }
}

package enum SQLiteLogSortOrder: Sendable {
    case newestFirst
    case oldestFirst
}

package struct SQLiteLogQuery: Sendable {
    package var from: Date?
    package var to: Date?
    package var levels: [String]?
    package var label: String?
    package var tag: String?
    package var appName: String?
    package var messageSearch: String?
    package var limit: Int?
    package var offset: Int?
    package var order: SQLiteLogSortOrder

    package init(
        from: Date?,
        to: Date?,
        levels: [String]?,
        label: String?,
        tag: String?,
        appName: String?,
        messageSearch: String?,
        limit: Int?,
        offset: Int?,
        order: SQLiteLogSortOrder
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
        self.order = order
    }
}
