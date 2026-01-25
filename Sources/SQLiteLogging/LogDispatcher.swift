import Foundation
import Logging
import SQLiteLoggingSQLite

actor LogDispatcher {
    private let store: SQLiteLogStore
    private let queueDepth: Int
    private let dropPolicy: DropPolicy?
    private let appName: String

    private var buffer: [LogEvent] = []
    private var bufferIndex = 0
    private var isProcessing = false
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastDropReport: ContinuousClock.Instant?
    private var droppedCounts: [Logger.Level: Int] = [:]
    private var isShutdown = false
    private var streamContinuations: [UUID: AsyncStream<SQLiteLogRecord>.Continuation] = [:]

    init(store: SQLiteLogStore, queueDepth: Int, dropPolicy: DropPolicy?, appName: String) {
        self.store = store
        self.queueDepth = max(1, queueDepth)
        self.dropPolicy = dropPolicy
        self.appName = appName
    }

    func enqueue(_ event: LogEvent) {
        if isShutdown { return }
        if shouldDrop(event) {
            recordDrop(event)
            reportDropsIfNeeded(force: false)
            return
        }
        buffer.append(event)
        startProcessingIfNeeded()
    }

    func flush() async {
        reportDropsIfNeeded(force: true)
        if !bufferIsEmpty {
            await withCheckedContinuation { continuation in
                flushWaiters.append(continuation)
                startProcessingIfNeeded()
            }
        }
        await store.flush()
    }

    func shutdown() async {
        isShutdown = true
        await flush()
        finishStreams()
        resolveShutdownWaiters()
    }

    func waitForShutdown() async {
        if isShutdown { return }
        await withCheckedContinuation { continuation in
            shutdownWaiters.append(continuation)
        }
    }

    private func startProcessingIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task { [weak self] in
            await self?.processLoop()
        }
    }

    private func processLoop() async {
        while let event = popFirst() {
            await send(event)
        }
        isProcessing = false
        resolveFlushWaitersIfNeeded()
    }

    private func send(_ event: LogEvent) async {
        let entry = SQLiteLogEntry(event)
        if let record = await store.append(entry) {
            broadcast(record)
        }
    }

    func stream() -> AsyncStream<SQLiteLogRecord> {
        AsyncStream { continuation in
            let id = UUID()
            streamContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeStream(id: id)
                }
            }
        }
    }

    private var bufferIsEmpty: Bool {
        buffer.count <= bufferIndex
    }

    private func popFirst() -> LogEvent? {
        guard bufferIndex < buffer.count else { return nil }
        let event = buffer[bufferIndex]
        bufferIndex += 1
        if bufferIndex > 1024 {
            buffer.removeFirst(bufferIndex)
            bufferIndex = 0
        }
        return event
    }

    private func shouldDrop(_ event: LogEvent) -> Bool {
        guard buffer.count - bufferIndex >= queueDepth else { return false }
        guard let dropPolicy else { return true }
        if event.level < dropPolicy.dropBelow {
            return true
        }
        _ = dropOldestEvent()
        return false
    }

    private func dropOldestEvent() -> LogEvent? {
        guard bufferIndex < buffer.count else { return nil }
        let event = buffer[bufferIndex]
        bufferIndex += 1
        if bufferIndex > 1024 {
            buffer.removeFirst(bufferIndex)
            bufferIndex = 0
        }
        recordDrop(event)
        return event
    }

    private func recordDrop(_ event: LogEvent) {
        droppedCounts[event.level, default: 0] += 1
    }

    private func reportDropsIfNeeded(force: Bool) {
        guard !droppedCounts.isEmpty else { return }
        let interval = dropPolicy?.reportInterval
        let now = ContinuousClock().now
        if force {
            emitDropSummary()
            lastDropReport = now
            droppedCounts.removeAll()
            return
        }
        guard let interval else { return }
        if let lastDropReport, lastDropReport.duration(to: now) >= interval {
            emitDropSummary()
            self.lastDropReport = now
            droppedCounts.removeAll()
        } else if lastDropReport == nil {
            lastDropReport = now
        }
    }

    private func emitDropSummary() {
        let summary = droppedCounts
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ", ")
        let message = "Dropped log events due to backpressure: \(summary)"
        let event = LogEvent(
            timestamp: Date(),
            level: .warning,
            message: message,
            label: "SQLiteLogging.DropPolicy",
            tag: "SQLiteLogging.DropPolicy",
            metadata: [:],
            metadataJSON: "{}",
            appName: appName,
            source: "SQLiteLogging",
            file: "",
            function: "",
            line: 0
        )
        buffer.append(event)
        startProcessingIfNeeded()
    }

    private func broadcast(_ record: SQLiteLogRecord) {
        for continuation in streamContinuations.values {
            continuation.yield(record)
        }
    }

    private func finishStreams() {
        let continuations = streamContinuations.values
        streamContinuations.removeAll()
        continuations.forEach { $0.finish() }
    }

    private func removeStream(id: UUID) {
        streamContinuations[id] = nil
    }

    private func resolveFlushWaitersIfNeeded() {
        guard bufferIsEmpty else { return }
        let waiters = flushWaiters
        flushWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func resolveShutdownWaiters() {
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
