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
    @State private var selectedLevels: Set<Logger.Level> = []
    @State private var lastSelectedLevel: Logger.Level?
    @State private var newestOnTop = true
    @State private var fromEnabled = false
    @State private var toEnabled = false
    @State private var fromDate = Date().addingTimeInterval(-3600)
    @State private var toDate = Date()
    @State private var limit = 200
    @State private var messageLineLimit = 3
    @State private var liveUpdatesEnabled = true
    @State private var filtersExpanded = false
    @State private var presentedFilterEditor: FilterEditor?
    
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
                .toolbar {
                    if hasActiveFilters {
                        ToolbarItem {
                            Button("Clear filters", systemImage: "line.3.horizontal.decrease.circle.badge.xmark") {
                                clearFilters()
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityHint("Shows all logs")
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search message")
                .sheet(item: $presentedFilterEditor) { editor in
                    switch editor {
                    case .dateRange:
                        DateRangeEditor(
                            fromEnabled: $fromEnabled,
                            toEnabled: $toEnabled,
                            fromDate: $fromDate,
                            toDate: $toDate
                        )
                    }
                }
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
            DisclosureGroup(isExpanded: $filtersExpanded) {
                TextField("Label", text: $labelFilter)
                    #if os(iOS) || os(tvOS) || os(watchOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                levelPicker

                HStack(spacing: 8) {
                    Toggle(isOn: $newestOnTop) {
                        Text("Newest first")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle(isOn: $liveUpdatesEnabled) {
                        Text("Live updates")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    presentedFilterEditor = .dateRange
                } label: {
                    HStack {
                        Label("Date range", systemImage: "calendar.badge.clock")
                        Spacer(minLength: 8)
                        Text(dateRangeSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(dateRangeSummary)

                HStack(spacing: 8) {
                    Stepper(value: $limit, in: 50...2000, step: 50) {
                        Text("Limit \(limit)")
                            .lineLimit(1)
                    }
                    .accessibilityLabel("Log limit")
                    .accessibilityValue("\(limit)")

                    Divider()

                    Stepper(value: $messageLineLimit, in: 1...100, step: 1) {
                        Text("Max lines \(messageLineLimit)")
                            .lineLimit(1)
                    }
                    .accessibilityLabel("Maximum message lines")
                    .accessibilityValue("\(messageLineLimit)")
                }

            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Filters")
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(filterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Levels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedLevels.isEmpty ? "All" : "\(selectedLevels.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Logger.Level.allCases.reversed(), id: \.self) { level in
                            LevelToggle(
                                level: level,
                                color: style.color(for: level),
                                isSelected: selectedLevels.contains(level)
                            ) {
                                toggle(level)
                            }
                            .id(level)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let selectedLevelToReveal else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selectedLevelToReveal, anchor: .center)
                    }
                }
            }
            .id(filtersExpanded)
        }
        .padding(.vertical, 2)
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
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
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
            if lastSelectedLevel == level {
                lastSelectedLevel = selectedLevelToReveal
            }
        } else {
            selectedLevels.insert(level)
            lastSelectedLevel = level
            if selectedLevels.count == Logger.Level.allCases.count {
                selectedLevels.removeAll()
                lastSelectedLevel = nil
            }
        }
    }

    private var selectedLevelToReveal: Logger.Level? {
        if let lastSelectedLevel, selectedLevels.contains(lastSelectedLevel) {
            return lastSelectedLevel
        }
        return Logger.Level.allCases.reversed().first(where: selectedLevels.contains)
    }

    private var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    private var activeFilterCount: Int {
        (selectedLevels.isEmpty ? 0 : 1) +
        (labelFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1) +
        (fromEnabled || toEnabled ? 1 : 0)
    }

    private var filterSummary: String {
        var parts = Logger.Level.allCases.reversed()
            .filter(selectedLevels.contains)
            .map { $0.rawValue.capitalized }

        let trimmedLabel = labelFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            parts.append("Label: \(trimmedLabel)")
        }
        if fromEnabled, toEnabled {
            parts.append("\(formattedFilterDate(fromDate))–\(formattedFilterDate(toDate))")
        } else if fromEnabled {
            parts.append("From \(formattedFilterDate(fromDate))")
        } else if toEnabled {
            parts.append("Until \(formattedFilterDate(toDate))")
        }

        return parts.isEmpty ? "All logs" : parts.joined(separator: " · ")
    }

    private func formattedFilterDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var dateRangeSummary: String {
        if fromEnabled, toEnabled {
            return "\(formattedFilterDate(fromDate))–\(formattedFilterDate(toDate))"
        } else if fromEnabled {
            return "After \(formattedFilterDate(fromDate))"
        } else if toEnabled {
            return "Before \(formattedFilterDate(toDate))"
        } else {
            return "Any time"
        }
    }

    private func clearFilters() {
        selectedLevels.removeAll()
        lastSelectedLevel = nil
        labelFilter = ""
        fromEnabled = false
        toEnabled = false
    }
}

private enum FilterEditor: String, Identifiable {
    case dateRange

    var id: Self { self }
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
        guard !levels.isEmpty else { return nil }
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
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? color : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle \(level.rawValue) logs")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct DateRangeEditor: View {
    @Environment(\.dismiss) private var dismiss

    @Binding private var fromEnabled: Bool
    @Binding private var toEnabled: Bool
    @Binding private var fromDate: Date
    @Binding private var toDate: Date

    @State private var draftFromEnabled: Bool
    @State private var draftToEnabled: Bool
    @State private var draftFromDate: Date
    @State private var draftToDate: Date

    init(
        fromEnabled: Binding<Bool>,
        toEnabled: Binding<Bool>,
        fromDate: Binding<Date>,
        toDate: Binding<Date>
    ) {
        _fromEnabled = fromEnabled
        _toEnabled = toEnabled
        _fromDate = fromDate
        _toDate = toDate
        _draftFromEnabled = State(initialValue: fromEnabled.wrappedValue)
        _draftToEnabled = State(initialValue: toEnabled.wrappedValue)
        _draftFromDate = State(initialValue: fromDate.wrappedValue)
        _draftToDate = State(initialValue: toDate.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Menu("Choose a quick range", systemImage: "clock.arrow.circlepath") {
                        Button("Last hour") {
                            selectRange(endingAt: Date(), duration: 60 * 60)
                        }
                        Button("Last 24 hours") {
                            selectRange(endingAt: Date(), duration: 24 * 60 * 60)
                        }
                        Button("Last 7 days") {
                            selectRange(endingAt: Date(), duration: 7 * 24 * 60 * 60)
                        }
                    }
                } header: {
                    Text("Quick range")
                }

                Section {
                    Toggle("Minimum date", isOn: $draftFromEnabled)
                    if draftFromEnabled {
                        DatePicker(
                            "From",
                            selection: $draftFromDate,
                            in: Date.distantPast...maximumFromDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Toggle("Maximum date", isOn: $draftToEnabled)
                    if draftToEnabled {
                        DatePicker(
                            "To",
                            selection: $draftToDate,
                            in: minimumToDate...Date.distantFuture,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } header: {
                    Text("Custom bounds")
                }

                if draftFromEnabled || draftToEnabled {
                    Section {
                        Button("Remove date range", role: .destructive) {
                            draftFromEnabled = false
                            draftToEnabled = false
                        }
                    }
                }
            }
            .navigationTitle("Date Range")
            #if os(iOS) || os(tvOS) || os(watchOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyChanges()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private var maximumFromDate: Date {
        draftToEnabled ? draftToDate : Date.distantFuture
    }

    private var minimumToDate: Date {
        draftFromEnabled ? draftFromDate : Date.distantPast
    }

    private func selectRange(endingAt endDate: Date, duration: TimeInterval) {
        draftFromEnabled = true
        draftToEnabled = true
        draftFromDate = endDate.addingTimeInterval(-duration)
        draftToDate = endDate
    }

    private func applyChanges() {
        fromEnabled = draftFromEnabled
        toEnabled = draftToEnabled
        fromDate = draftFromDate
        toDate = draftToDate
        dismiss()
    }
}

private struct LogRow: View {
    let record: LogRecord
    let style: SQLiteLogViewerStyle
    let messageLineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                LevelPill(level: record.level, color: levelColor)
                Text(record.label)
                    .font(style.logFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !record.tag.isEmpty, record.tag != record.label {
                    Text("•")
                        .font(style.logFont)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(record.tag)
                        .font(style.logFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(formattedTimestamp)
                    .font(style.logFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            
            messageWithMetadata
                .font(style.logFont)
                .lineLimit(messageLineLimit)
        }
        .padding(.vertical, 2)
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

    private var messageWithMetadata: Text {
        var parts = [Text(record.message).foregroundColor(.primary)]
        let hasMetadata = !record.metadataJSON.isEmpty && record.metadataJSON != "{}"
        guard hasMetadata else { return combinedText(parts) }

        parts.append(Text("  ·  ").foregroundColor(.secondary.opacity(0.6)))

        guard let metadataItems else {
            parts.append(Text(record.metadataJSON).foregroundColor(.secondary))
            return combinedText(parts)
        }

        for (index, item) in metadataItems.enumerated() {
            if index > 0 {
                parts.append(Text("  "))
            }
            parts.append(
                Text(item.key)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            )
            parts.append(Text("=\(item.value)").foregroundColor(.secondary.opacity(0.82)))
        }
        return combinedText(parts)
    }

    private func combinedText(_ parts: [Text]) -> Text {
        guard let first = parts.first else { return Text("") }
        return parts.dropFirst().reduce(first) { result, next in
            Text("\(result)\(next)")
        }
    }

    private var metadataItems: [(key: String, value: String)]? {
        guard let data = record.metadataJSON.data(using: .utf8) else { return nil }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object.keys.sorted().map { key in
                (key: key, value: metadataValueDescription(object[key]))
            }
        } catch {
            return nil
        }
    }

    private func metadataValueDescription(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let string = value as? String {
            return string
        }
        if JSONSerialization.isValidJSONObject(value) {
            do {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                if let string = String(data: data, encoding: .utf8) {
                    return string
                }
            } catch {
                return String(describing: value)
            }
        }
        return String(describing: value)
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
