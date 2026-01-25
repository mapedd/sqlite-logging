import Logging

public struct DropPolicy: Sendable {
    public var dropBelow: Logger.Level
    public var reportInterval: Duration?

    public init(
        dropBelow: Logger.Level = .info,
        reportInterval: Duration? = .seconds(30)
    ) {
        self.dropBelow = dropBelow
        self.reportInterval = reportInterval
    }
}
