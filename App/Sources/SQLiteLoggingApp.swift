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
        return try? SQLiteLoggingSystem.bootstrap(configuration: configuration)
    }()
}
