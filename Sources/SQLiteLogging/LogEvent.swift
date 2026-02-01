import Foundation
import Logging

public struct LogEvent: Sendable, Equatable {
    public let timestamp: Date
    public let level: Logger.Level
    public let message: String
    public let label: String
    public let tag: String
    public let metadata: Logger.Metadata
    public let metadataJSON: String
    public let appName: String
    public let source: String
    public let file: String
    public let function: String
    public let line: UInt

    public init(
        timestamp: Date,
        level: Logger.Level,
        message: String,
        label: String,
        tag: String,
        metadata: Logger.Metadata,
        metadataJSON: String,
        appName: String,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.label = label
        self.tag = tag
        self.metadata = metadata
        self.metadataJSON = metadataJSON
        self.appName = appName
        self.source = source
        self.file = file
        self.function = function
        self.line = line
    }
}
