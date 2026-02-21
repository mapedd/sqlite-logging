import Logging
import SQLiteLogging
import SwiftUI

@main
struct SQLiteLoggingApp: App {
    private let manager = AppState.manager

    var body: some Scene {
        WindowGroup {
            if let manager {
                ContentView(manager: manager)
            } else {
                ContentUnavailableView("Logging Unavailable", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

private enum AppState {
    static let manager: SQLiteLogManager? = {
        let configuration = SQLiteLoggingConfiguration(
            appName: "SQLiteLoggingApp",
            database: .default()
        )
        guard let components = try? SQLiteLoggingSystem.make(configuration: configuration) else {
            return nil
        }
        LoggingSystem.bootstrap(components.handlerFactory)
        return components.manager
    }()
}
