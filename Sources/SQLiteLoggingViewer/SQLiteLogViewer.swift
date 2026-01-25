import Logging
import SQLiteLogging
import SwiftUI

public struct SQLiteLogViewer: View {
    private let manager: SQLiteLogManager
    private let style: SQLiteLogViewerStyle

    @State private var searchText = ""
    @State private var labelFilter = ""
    @State private var selectedLevels = Set(Logger.Level.allCases)
    @State private var fromEnabled = false
    @State private var toEnabled = false
    @State private var fromDate = Date().addingTimeInterval(-3600)
    @State private var toDate = Date()
    @State private var limit = 200
    @State private var state: LoadState = .idle

    public init(
        manager: SQLiteLogManager,
        style: SQLiteLogViewerStyle = SQLiteLogViewerStyle()
    ) {
        self.manager = manager
        self.style = style
    }

    public var body: some View {
        NavigationStack {
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
            .task(id: filterState) {
                await load()
            }
        }
    }

    private var filtersSection: some View {
        Section("Filters") {
            TextField("Label", text: $labelFilter)
                #if os(iOS) || os(tvOS) || os(watchOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif

            levelPicker

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

    @MainActor
    private func load() async {
        state = .loading
        let query = LogQuery(
            from: filterState.from,
            to: filterState.to,
            levels: filterState.levelsFilter,
            label: filterState.labelFilter,
            messageSearch: filterState.searchFilter,
            limit: filterState.limit
        )
        do {
            let records = try await manager.query(query)
            state = .loaded(records)
        } catch {
            state = .failed("Failed to load logs.")
        }
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
