import Foundation
import Logging
public struct SQLiteLogHandler: LogHandler {
    public var logLevel: Logger.Level
    public var metadata: Logger.Metadata

    private let label: String
    private let appName: String
    private let dispatcher: LogDispatcher

    init(label: String, appName: String, dispatcher: LogDispatcher) {
        self.label = label
        self.appName = appName
        self.dispatcher = dispatcher
        self.metadata = [:]
        self.logLevel = .info
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        if level < logLevel { return }
        let combined = self.metadata.merging(metadata ?? [:]) { _, new in new }
        let metadataJSON = MetadataJSONEncoder.encode(combined)
        let event = LogEvent(
            timestamp: Date(),
            level: level,
            message: message.description,
            label: label,
            tag: label,
            metadata: combined,
            metadataJSON: metadataJSON,
            appName: appName,
            source: source,
            file: file,
            function: function,
            line: line
        )
        Task {
            await dispatcher.enqueue(event)
        }
    }
}
