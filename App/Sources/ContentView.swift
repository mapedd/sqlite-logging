import Logging
import SQLiteLogging
import SQLiteLoggingViewer
import SwiftUI

struct ContentView: View {
    let manager: SQLiteLogManager
    @State var index = 0
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
        isGenerating = false
    }
  
    private func generateRandomLog() async {
        let level = Logger.Level.allCases.randomElement() ?? .info
        let base = Self.soundPhrases.randomElement() ?? "ambient noise detected"
        let message = "\(base) [#\(index)]"
        index += 1
        let metadata = generateRandomMetadata()

        await manager.record(
            timestamp: Date(),
            level: level,
            message: message,
            metadata: metadata,
            label: label,
            source: label,
            file: "ContentView.swift",
            function: "generateRandomLog()",
            line: UInt(arc4random()) & 1000
        )
    }

    private func generateRandomMetadata() -> Logger.Metadata {
        let allMetadataOptions: [(String, Logger.MetadataValue)] = [
            ("userId", .string("user_\(Int.random(in: 1000...9999))")),
            ("messageType", .string(Self.messageTypes.randomElement() ?? "unknown")),
            ("error", .string(Self.errorMessages.randomElement() ?? "none")),
            ("requestId", .string("req_\(UUID().uuidString.prefix(8))")),
            ("service", .string(Self.services.randomElement() ?? "default")),
            ("priority", .stringConvertible(Int.random(in: 1...5))),
            ("duration", .stringConvertible(Double.random(in: 0.001...5.0))),
            ("bytes", .stringConvertible(Int.random(in: 100...100000))),
        ]

        // Select 1-4 random metadata items
        let count = Int.random(in: 1...4)
        let shuffled = allMetadataOptions.shuffled()
        let selected = Array(shuffled.prefix(count))

        return Dictionary(uniqueKeysWithValues: selected)
    }

    private static let soundPhrases = [
        "soft hiss from the vent that gradually increases in intensity and then fades away into silence",
        "distant rumble under the floor",
        "sharp clang near the dock door that reverberates throughout the entire warehouse space for several seconds",
        "rapid tapping on the console",
        "low hum in the engine bay that persists continuously with slight variations in pitch and amplitude throughout the day",
        "faint buzz in the wiring panel",
        "dry rattle from the cabinet that occurs intermittently whenever the air conditioning system cycles on and off",
        "metallic click on startup",
        "slow drip echoing in the corridor",
        "brief pop in the speaker line",
        "steady whir from the cooling fan maintaining constant speed and creating a soothing background white noise effect",
        "short thud by the storage rack",
        "sudden squeak on the hinge that startles nearby workers and draws attention to the need for maintenance oiling",
        "muted thump behind the wall",
        "soft crackle over the intercom",
        "light scrape along the rail that indicates possible misalignment of the track requiring immediate inspection",
        "hollow knock on the frame",
        "thin whistle in the pipe that suggests high pressure buildup in the system that needs to be monitored closely",
        "crisp snap near the breaker",
        "gentle chime from the panel that signals the completion of the automated sequence and ready status for next operation",
    ]

    private static let messageTypes = [
        "request", "response", "event", "error", "notification", "heartbeat", "sync"
    ]

    private static let errorMessages = [
        "none", "timeout", "connection_failed", "validation_error", "not_found", "rate_limited"
    ]

    private static let services = [
        "api-gateway", "auth-service", "database", "cache", "queue", "storage", "logger"
    ]
}

struct LogViewerContainer: View {
    let manager: SQLiteLogManager

    var body: some View {
        SQLiteLogViewer(manager: manager)
    }
}
