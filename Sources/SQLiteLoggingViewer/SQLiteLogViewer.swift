import Logging
import SQLiteLogging
import SwiftUI

public struct SQLiteLogViewer: View {
    private let manager: SQLiteLogManager
    private let style: SQLiteLogViewerStyle
    private let liveUpdateDebounce: Duration?

    @State private var searchText = ""
    @State private var labelFilter = ""
    @State private var selectedLevels = Set(Logger.Level.allCases)
    @State private var newestOnTop = true
    @State private var fromEnabled = false
    @State private var toEnabled = false
    @State private var fromDate = Date().addingTimeInterval(-3600)
    @State private var toDate = Date()
    @State private var limit = 200
    @State private var liveUpdatesEnabled = true
    @State private var isAtBottom = true
    @State private var pendingScrollToBottomID: Int64?
    @State private var filtersExpanded = true
    @State private var state: LoadState = .idle

    public init(
        manager: SQLiteLogManager,
        style: SQLiteLogViewerStyle = SQLiteLogViewerStyle(),
        liveUpdateDebounce: Duration? = .milliseconds(300)
    ) {
        self.manager = manager
        self.style = style
        self.liveUpdateDebounce = liveUpdateDebounce
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    filtersSection
                    resultsSection
                }
                #if os(iOS) || os(tvOS) || os(watchOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .navigationTitle("Logs")
                .searchable(text: $searchText, prompt: "Search message")
                .task(id: streamState) {
                    await loadInitial()
                    guard liveUpdatesEnabled else { return }
                    await observeLiveLogs()
                }
                .onChange(of: pendingScrollToBottomID) { _, newValue in
                    guard let target = newValue else { return }
                    proxy.scrollTo(target, anchor: .bottom)
                    pendingScrollToBottomID = nil
                }
            }
        }
    }

    private var filtersSection: some View {
            Section {
                DisclosureGroup("Filters", isExpanded: $filtersExpanded) {
                    TextField("Label", text: $labelFilter)
                        #if os(iOS) || os(tvOS) || os(watchOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif

                    levelPicker

                    Toggle("Newest on top", isOn: $newestOnTop)

                    Toggle("Live updates", isOn: $liveUpdatesEnabled)

                    Toggle("From date", isOn: $fromEnabled)
                    if fromEnabled {
                        DatePicker(
                            "From",
                            selection: $fromDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Toggle("To date", isOn: $toEnabled)
                    if toEnabled {
                        DatePicker(
                            "To",
                            selection: $toDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Stepper("Limit: \(limit)", value: $limit, in: 50...2000, step: 50)
                }
            }
        }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Levels")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(Logger.Level.allCases, id: \.self) { level in
                    LevelToggle(
                        level: level,
                        color: style.color(for: level),
                        isSelected: selectedLevels.contains(level)
                    ) {
                        toggle(level)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var resultsSection: some View {
        Section("Results") {
            switch state {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.secondary)
            case .loaded(let records):
                if records.isEmpty {
                    Text("No logs match the current filters.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records, id: \.id) { record in
                        LogRow(record: record, style: style)
                            .onAppear {
                                if !newestOnTop, record.id == bottomRecordID {
                                    isAtBottom = true
                                }
                            }
                            .onDisappear {
                                if !newestOnTop, record.id == bottomRecordID {
                                    isAtBottom = false
                                }
                            }
                    }
                }
            }
        }
    }

    private var filterState: FilterState {
        FilterState(
            searchText: searchText,
            label: labelFilter,
            levels: selectedLevels,
            from: fromEnabled ? fromDate : nil,
            to: toEnabled ? toDate : nil,
            limit: limit
        )
    }

    private var streamState: StreamState {
        StreamState(
            filter: filterState,
            liveUpdatesEnabled: liveUpdatesEnabled,
            debounce: liveUpdateDebounce,
            newestOnTop: newestOnTop
        )
    }

    @MainActor
    private func loadInitial() async {
        if shouldShowLoadingState {
            state = .loading
        }
        let query = currentQuery
        do {
            let records = try await manager.query(query)
            if Task.isCancelled { return }
            let sorted = sortedRecords(records)
            state = .loaded(sorted)
            if shouldStickToBottom {
                pendingScrollToBottomID = sorted.last?.id
            }
        } catch {
            if Task.isCancelled { return }
            state = .failed("Failed to load logs.")
        }
    }

    private var shouldShowLoadingState: Bool {
        switch state {
        case .idle, .failed:
            return true
        case .loading, .loaded:
            return false
        }
    }

    private var currentQuery: LogQuery {
        LogQuery(
            from: filterState.from,
            to: filterState.to,
            levels: filterState.levelsFilter,
            label: filterState.labelFilter,
            messageSearch: filterState.searchFilter,
            limit: filterState.limit
        )
    }

    private func observeLiveLogs() async {
        let stream = await manager.logStream(query: currentQuery)
        if let debounce = liveUpdateDebounce {
            await observeDebounced(stream, interval: debounce)
        } else {
            for await record in stream {
                await applyRecords([record], reset: false)
            }
        }
    }

    private func observeDebounced(
        _ stream: AsyncStream<LogRecord>,
        interval: Duration
    ) async {
        let buffer = DebounceBuffer()
        var flushTask: Task<Void, Never>?

        for await record in stream {
            await buffer.append(record)
            flushTask?.cancel()
            flushTask = Task {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                let records = await buffer.drain()
                await applyRecords(records, reset: false)
            }
        }

        flushTask?.cancel()
        let remaining = await buffer.drain()
        await applyRecords(remaining, reset: false)
    }

    @MainActor
    private func applyRecords(_ newRecords: [LogRecord], reset: Bool) async {
        guard !newRecords.isEmpty else { return }
        var updated: [LogRecord]
        switch state {
        case .loaded(let records) where !reset:
            updated = records + newRecords
        default:
            updated = newRecords
        }
        updated = sortedRecords(updated)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        state = .loaded(updated)
        if shouldStickToBottom {
            pendingScrollToBottomID = updated.last?.id
        }
    }

    private var shouldStickToBottom: Bool {
        !newestOnTop && isAtBottom
    }

    private func sortedRecords(_ records: [LogRecord]) -> [LogRecord] {
        records.sorted {
            if $0.timestamp != $1.timestamp {
                return newestOnTop ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp
            }
            return newestOnTop ? $0.id > $1.id : $0.id < $1.id
        }
    }

    private var bottomRecordID: Int64? {
        guard case .loaded(let records) = state else { return nil }
        return records.last?.id
    }

    private func toggle(_ level: Logger.Level) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
    }
}

private enum LoadState: Equatable {
    case idle
    case loading
    case loaded([LogRecord])
    case failed(String)
}

private struct FilterState: Equatable {
    let searchText: String
    let label: String
    let levels: Set<Logger.Level>
    let from: Date?
    let to: Date?
    let limit: Int

    var labelFilter: String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var searchFilter: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var levelsFilter: [Logger.Level]? {
        let all = Set(Logger.Level.allCases)
        if levels == all {
            return nil
        }
        return levels.sorted { $0.rawValue < $1.rawValue }
    }
}

private struct StreamState: Equatable {
    let filter: FilterState
    let liveUpdatesEnabled: Bool
    let debounce: Duration?
    let newestOnTop: Bool
}

private struct LevelToggle: View {
    let level: Logger.Level
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(level.rawValue.uppercased())
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? color : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle \(level.rawValue) logs")
    }
}

private struct LogRow: View {
    let record: LogRecord
    let style: SQLiteLogViewerStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(record.level.rawValue.uppercased())
                    .font(style.logFont.weight(.semibold))
                    .foregroundStyle(levelColor)
                Text(record.message)
                    .font(style.logFont)
                    .foregroundStyle(levelColor)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(formattedDate)
                Text(record.label)
                if !record.metadataJSON.isEmpty, record.metadataJSON != "{}" {
                    Text(record.metadataJSON)
                        .lineLimit(1)
                }
            }
            .font(style.logFont)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        Self.formatter.string(from: record.timestamp)
    }

    private var levelColor: Color {
        style.color(for: record.level)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}

private actor DebounceBuffer {
    private var records: [LogRecord] = []

    func append(_ record: LogRecord) {
        records.append(record)
    }

    func drain() -> [LogRecord] {
        let drained = records
        records.removeAll()
        return drained
    }
}

#if DEBUG
struct SQLiteLogViewer_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer()
    }
}

private struct PreviewContainer: View {
    @State private var manager: SQLiteLogManager?

    var body: some View {
        Group {
            if let manager {
                SQLiteLogViewer(manager: manager)
            } else {
                ProgressView("Loading sample logs…")
                    .task {
                        manager = await PreviewData.shared.manager()
                    }
            }
        }
    }
}

private actor PreviewData {
    static let shared = PreviewData()
    private var cachedManager: SQLiteLogManager?

    func manager() async -> SQLiteLogManager {
        if let cachedManager {
            return cachedManager
        }

        let configuration = SQLiteLoggingConfiguration(
            appName: "SQLiteLogViewerPreview",
            queueDepth: 64,
            dropPolicy: nil,
            database: .inMemory()
        )

        let manager = try! SQLiteLoggingSystem.bootstrap(configuration: configuration)
        let logger = Logger(label: "Preview")

        logger.trace("Trace sample log", metadata: ["scope": "preview"])
        logger.debug("Debug sample log", metadata: ["scope": "preview"])
        logger.info("Info sample log", metadata: ["scope": "preview"])
        logger.notice("Notice sample log", metadata: ["scope": "preview"])
        logger.warning("Warning sample log", metadata: ["scope": "preview"])
        logger.error("Error sample log", metadata: ["scope": "preview"])
        logger.critical("Critical sample log", metadata: ["scope": "preview"])

        await manager.flush()
        cachedManager = manager
        return manager
    }
}
#endif
