import Foundation
import Logging
import SQLiteLoggingSQLite

public struct SQLiteLoggingSystemComponents {
    public let manager: SQLiteLogManager
    public let handlerFactory: @Sendable (String) -> LogHandler
}

public enum SQLiteLoggingSystem {
    public static func make(
        configuration: SQLiteLoggingConfiguration = SQLiteLoggingConfiguration()
    ) throws -> SQLiteLoggingSystemComponents {
        let storeStorage: SQLiteLogStoreStorage
        switch configuration.database.storage {
        case .inMemory:
            storeStorage = .inMemory
        case .file(let url):
            storeStorage = .file(url)
        }
        let store = try SQLiteLogStore(
            storage: storeStorage,
            maxDatabaseBytes: configuration.database.maxDatabaseBytes
        )

        let dispatcher = LogDispatcher(
            store: store,
            queueDepth: configuration.queueDepth,
            dropPolicy: configuration.dropPolicy,
            appName: configuration.appName
        )

        let manager = SQLiteLogManager(
            dispatcher: dispatcher,
            store: store,
            databaseStorage: configuration.database.storage,
            appName: configuration.appName
        )

        let handlerFactory: @Sendable (String) -> LogHandler = { label in
          SQLiteLogHandler(
            label: label,
            appName: configuration.appName,
            dispatcher: dispatcher
          )
        }

        return SQLiteLoggingSystemComponents(manager: manager, handlerFactory: handlerFactory)
    }
}
