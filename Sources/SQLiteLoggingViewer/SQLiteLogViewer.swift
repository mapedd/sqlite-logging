import AsyncAlgorithms
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
    @State private var messageLineLimit = 1
    @State private var liveUpdatesEnabled = true
    @State private var filtersExpanded = false
    
    @State private var isAtBottom = true
    @State private var pendingScrollToBottomID: Int64?
    @State private var state: LoadState = .idle
    @State private var newlyAddedLogIDs: Set<Int64> = []
    @State private var selectedLogRecord: LogRecord?
    @State private var showClearLogsAlert = false

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
                let list = List {
                    filtersSection
                    resultsSection
                }
                #if os(iOS) || os(tvOS) || os(watchOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .navigationTitle("Logs")
                #if os(iOS) || os(tvOS) || os(watchOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .searchable(text: $searchText, prompt: "Search message")
                #if os(iOS) || os(tvOS) || os(watchOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .task(id: streamState) {
                    await loadInitial()
                    guard liveUpdatesEnabled else { return }
                    await observeLiveLogs()
                }
                if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
                    list
                        .sheet(item: $selectedLogRecord) { record in
                            LogDetailView(
                                manager: manager,
                                currentRecord: record,
                                style: style,
                                onDismiss: {
                                    selectedLogRecord = nil
                                }
                            )
                        }
                        .onChange(of: pendingScrollToBottomID) { _, newValue in
                            handlePendingScroll(newValue, proxy: proxy)
                        }
                } else {
                    list
                        .sheet(item: $selectedLogRecord) { record in
                            LogDetailView(
                                manager: manager,
                                currentRecord: record,
                                style: style,
                                onDismiss: {
                                    selectedLogRecord = nil
                                }
                            )
                        }
                        .onChange(of: pendingScrollToBottomID) { newValue in
                            handlePendingScroll(newValue, proxy: proxy)
                        }
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
                    
                    Stepper("Message lines: \(messageLineLimit)", value: $messageLineLimit, in: 1...100, step: 1)
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
        Section {
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
                        LogRow(record: record, style: style, messageLineLimit: messageLineLimit)
                            .contentShape(Rectangle())
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
                            .onTapGesture {
                                selectedLogRecord = record
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        } header: {
            HStack {
                Text("Results")
                Spacer()
                Button {
                    showClearLogsAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Clear All Logs?", isPresented: $showClearLogsAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task { await clearAllLogs() }
            }
        } message: {
            Text("This will permanently delete all log entries from the database.")
        }
    }

    @MainActor
    private func clearAllLogs() async {
        do {
            try await manager.clearAllLogs()
            // Refresh the view to show empty state
            await refreshFromDatabase(showLoading: false)
        } catch {
            state = .failed("Failed to clear logs: \(error.localizedDescription)")
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
        await refreshFromDatabase(showLoading: shouldShowLoadingState)
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
            limit: filterState.limit,
            order: newestOnTop ? .newestFirst : .oldestFirst
        )
    }

    private func observeLiveLogs() async {
        let stream = await manager.logStream(query: currentQuery)
        if let debounce = liveUpdateDebounce {
            let debounced = stream.debounce(for: debounce, clock: ContinuousClock())
            for await _ in debounced {
                await refreshFromDatabase(showLoading: false)
            }
        } else {
            for await _ in stream {
                await refreshFromDatabase(showLoading: false)
            }
        }
    }

    @MainActor
    private func refreshFromDatabase(showLoading: Bool) async {
        if showLoading {
            state = .loading
        }
        do {
            let newRecords = try await manager.query(currentQuery)
            if Task.isCancelled { return }
            
            // Track newly added records for animation
            if case .loaded(let oldRecords) = state {
                let oldIDs = Set(oldRecords.map { $0.id })
                let newIDs = Set(newRecords.map { $0.id })
                let addedIDs = newIDs.subtracting(oldIDs)
                newlyAddedLogIDs = addedIDs
                
                // Clear the animation flag after a delay
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    await MainActor.run {
                        newlyAddedLogIDs.removeAll()
                    }
                }
            }
            
            state = .loaded(newRecords)
            if shouldStickToBottom {
                pendingScrollToBottomID = newRecords.last?.id
            }
        } catch {
            if Task.isCancelled { return }
            state = .failed("Failed to load logs.")
        }
    }

    private var shouldStickToBottom: Bool {
        !newestOnTop && isAtBottom
    }

    private var bottomRecordID: Int64? {
        guard case .loaded(let records) = state else { return nil }
        return records.last?.id
    }

    @MainActor
    private func handlePendingScroll(
        _ targetID: Int64?,
        proxy: ScrollViewProxy
    ) {
        guard let targetID else { return }
        proxy.scrollTo(targetID, anchor: .bottom)
        pendingScrollToBottomID = nil
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
    let messageLineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: Level + Timestamp
            HStack(spacing: 8) {
                LevelPill(level: record.level, color: levelColor)
                Spacer()
                Text(formattedTimestamp)
                    .font(style.logFont)
                    .foregroundStyle(.secondary)
            }
            
            // Line 2: Label + Tag
            HStack(spacing: 8) {
                Text(record.label)
                    .font(style.logFont)
                    .foregroundStyle(.secondary)
                if !record.tag.isEmpty, record.tag != record.label {
                    Text("•")
                        .font(style.logFont)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(record.tag)
                        .font(style.logFont)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            // Line 3+: Message + Metadata
            Text(messageWithMetadata)
                .font(style.logFont)
                .foregroundStyle(.primary)
                .lineLimit(messageLineLimit)
        }
        .padding(.vertical, 4)
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let now = Date()
        
        // Check if the log is from today
        if calendar.isDate(record.timestamp, inSameDayAs: now) {
            // Show only time with milliseconds for today
            formatter.dateFormat = "HH:mm:ss.SSS"
        } else {
            // Show date + time with milliseconds for other days
            formatter.dateFormat = "dd/MM/yy HH:mm:ss.SSS"
        }
        return formatter.string(from: record.timestamp)
    }

    private var levelColor: Color {
        style.color(for: record.level)
    }

    private var messageWithMetadata: String {
        let hasMetadata = !record.metadataJSON.isEmpty && record.metadataJSON != "{}"
        guard hasMetadata else { return record.message }
        return "\(record.message) | \(record.metadataJSON)"
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

        let components = try! SQLiteLoggingSystem.make(configuration: configuration)
        LoggingSystem.bootstrap(components.handlerFactory)
        let manager = components.manager
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
