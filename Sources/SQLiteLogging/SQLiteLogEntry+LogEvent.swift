import Foundation
import SQLiteLoggingSQLite

extension SQLiteLogEntry {
    init(_ event: LogEvent) {
        self.init(
            uuid: event.uuid.uuidString,
            timestamp: event.timestamp,
            level: event.level.rawValue,
            label: event.label,
            tag: event.tag,
            appName: event.appName,
            message: event.message,
            metadataJSON: event.metadataJSON,
            source: event.source,
            file: event.file,
            function: event.function,
            line: Int64(event.line)
        )
    }
}
