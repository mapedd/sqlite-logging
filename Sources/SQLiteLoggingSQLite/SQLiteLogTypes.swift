import Foundation
import StructuredQueriesSQLite

package struct SQLiteLogEntry: Sendable {
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

    package init(
        from: Date?,
        to: Date?,
        levels: [String]?,
        label: String?,
        tag: String?,
        appName: String?,
        messageSearch: String?,
        limit: Int?,
        offset: Int?
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
