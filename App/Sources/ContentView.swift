import Logging
import SQLiteLogging
import SQLiteLoggingViewer
import SwiftUI

struct ContentView: View {
    let manager: SQLiteLogManager
    private let logger = Logger(label: "SQLiteLoggingApp")
    private let label = "SQLiteLoggingApp"
    @State private var hasSeeded = false

    var body: some View {
        LogViewerContainer(manager: manager)
            .task {
                await seedLogsIfNeeded()
            }
    }

    @MainActor
    private func seedLogsIfNeeded() async {
        guard !hasSeeded else { return }
        hasSeeded = true
        await seedLogs()
        logger.info("Viewer launched", metadata: ["screen": "content"])
    }

    private func seedLogs() async {
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        let levels: [Logger.Level] = [
            .trace, .debug, .info, .notice, .warning, .error, .critical,
        ]
        let soundPhrases = [
            "soft hiss from the vent",
            "distant rumble under the floor",
            "sharp clang near the dock door",
            "rapid tapping on the console",
            "low hum in the engine bay",
            "faint buzz in the wiring panel",
            "dry rattle from the cabinet",
            "metallic click on startup",
            "slow drip echoing in the corridor",
            "brief pop in the speaker line",
            "steady whir from the cooling fan",
            "short thud by the storage rack",
            "sudden squeak on the hinge",
            "muted thump behind the wall",
            "soft crackle over the intercom",
            "light scrape along the rail",
            "hollow knock on the frame",
            "thin whistle in the pipe",
            "crisp snap near the breaker",
            "gentle chime from the panel",
        ]

        for index in 1...100 {
            guard let level = levels.randomElement() else { continue }
            let timestamp = Date(
                timeIntervalSince1970: Double.random(
                    in: start.timeIntervalSince1970...now.timeIntervalSince1970
                )
            )
            let base = soundPhrases.randomElement() ?? "ambient noise detected"
            let message = "\(base) [#\(index)]"
            let metadata: Logger.Metadata = [
                "seed": "true",
                "index": .stringConvertible(index),
            ]

            await manager.record(
                timestamp: timestamp,
                level: level,
                message: message,
                metadata: metadata,
                label: label,
                source: label,
                file: "ContentView.swift",
                function: "seedLogs()",
                line: 0
            )
        }

        await manager.flush()
    }
}

struct LogViewerContainer: View {
    let manager: SQLiteLogManager

    var body: some View {
        SQLiteLogViewer(manager: manager)
    }
}
