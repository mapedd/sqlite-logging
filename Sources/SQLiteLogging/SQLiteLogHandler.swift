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

    public func log(event: Logging.LogEvent) {
        if event.level < logLevel { return }
        let combined = self.metadata.merging(event.metadata ?? [:]) { _, new in new }
        let metadataJSON = MetadataJSONEncoder.encode(combined)
        let storedEvent = LogEvent(
            timestamp: Date(),
            level: event.level,
            message: event.message.description,
            label: label,
            tag: label,
            metadata: combined,
            metadataJSON: metadataJSON,
            appName: appName,
            source: event.source,
            file: event.file,
            function: event.function,
            line: event.line
        )
        Task {
            await dispatcher.enqueue(storedEvent)
        }
    }
}
