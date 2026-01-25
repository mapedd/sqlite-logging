import Foundation

public enum SQLiteDatabaseStorage: Sendable, Equatable {
    case inMemory
    case file(URL)
}

public struct SQLiteDatabaseConfiguration: Sendable {
    public var storage: SQLiteDatabaseStorage
    public var maxDatabaseBytes: Int64?

    public init(
        storage: SQLiteDatabaseStorage,
        maxDatabaseBytes: Int64? = nil
    ) {
        self.storage = storage
        self.maxDatabaseBytes = maxDatabaseBytes
    }

    public static func `default`(
        fileName: String = "sqlite-logs.sqlite",
        maxDatabaseBytes: Int64? = nil
    ) -> SQLiteDatabaseConfiguration {
        let directory = Self.defaultDocumentsDirectory()
        return SQLiteDatabaseConfiguration(
            storage: .file(directory.appendingPathComponent(fileName)),
            maxDatabaseBytes: maxDatabaseBytes
        )
    }

    public static func inMemory(maxDatabaseBytes: Int64? = nil) -> SQLiteDatabaseConfiguration {
        SQLiteDatabaseConfiguration(
            storage: .inMemory,
            maxDatabaseBytes: maxDatabaseBytes
        )
    }

    private static func defaultDocumentsDirectory() -> URL {
        let candidates = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let first = candidates.first {
            return first
        }
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
        #else
        return FileManager.default.temporaryDirectory
        #endif
    }
}

public struct SQLiteLoggingConfiguration: Sendable {
    public var appName: String
    public var queueDepth: Int
    public var dropPolicy: DropPolicy?
    public var database: SQLiteDatabaseConfiguration

    public init(
        appName: String = ProcessInfo.processInfo.processName,
        queueDepth: Int = 1024,
        dropPolicy: DropPolicy? = nil,
        database: SQLiteDatabaseConfiguration = .default()
    ) {
        self.appName = appName
        self.queueDepth = max(1, queueDepth)
        self.dropPolicy = dropPolicy
        self.database = database
    }
}
