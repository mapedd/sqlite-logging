import Foundation
import Logging
import SQLiteLoggingSQLite

public enum SQLiteLoggingSystem {
    @discardableResult
    public static func bootstrap(
        configuration: SQLiteLoggingConfiguration = SQLiteLoggingConfiguration()
    ) throws -> SQLiteLogManager {
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

        LoggingSystem.bootstrap { label in
            SQLiteLogHandler(label: label, appName: configuration.appName, dispatcher: dispatcher)
        }

        return SQLiteLogManager(
            dispatcher: dispatcher,
            store: store,
            databaseStorage: configuration.database.storage,
            appName: configuration.appName
        )
    }
}
