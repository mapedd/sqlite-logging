import Logging
import SQLiteLogging
import SQLiteLoggingViewer
import SwiftUI

struct ContentView: View {
    let manager: SQLiteLogManager
    private let label = "SQLiteLoggingApp"
    @State private var isGenerating = false

    var body: some View {
        LogViewerContainer(manager: manager)
            .task {
                guard beginGeneration() else { return }
                await generateLogsLoop()
            }
    }
  
    private func beginGeneration() -> Bool {
        guard !isGenerating else { return false }
        isGenerating = true
        return true
    }

    private func generateLogsLoop() async {
        while !Task.isCancelled {
            await generateRandomLog()
            try? await Task.sleep(for: .seconds(1))
        }
        await MainActor.run {
            isGenerating = false
        }
    }

    private func generateRandomLog() async {
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        let timestamp = Date(
            timeIntervalSince1970: Double.random(
                in: start.timeIntervalSince1970...now.timeIntervalSince1970
            )
        )
        let level = Logger.Level.allCases.randomElement() ?? .info
        let base = Self.soundPhrases.randomElement() ?? "ambient noise detected"
        let suffix = Int.random(in: 1000...9999)
        let message = "\(base) [#\(suffix)]"
        let metadata: Logger.Metadata = [
            "generator": "live",
            "window": "last-hour",
        ]

        await manager.record(
            timestamp: timestamp,
            level: level,
            message: message,
            metadata: metadata,
            label: label,
            source: label,
            file: "ContentView.swift",
            function: "generateRandomLog()",
            line: 0
        )
    }

    private static let soundPhrases = [
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
}

struct LogViewerContainer: View {
    let manager: SQLiteLogManager

    var body: some View {
        SQLiteLogViewer(manager: manager)
    }
}
