import Logging
import SQLiteLogging
import SwiftUI

@MainActor
struct LogDetailView: View {
    let manager: SQLiteLogManager
    @State var currentRecord: LogRecord
    let style: SQLiteLogViewerStyle
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var canGoPrevious = false
    @State private var canGoNext = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        levelPillRow
                        detailRow("Timestamp", value: formattedDate(currentRecord.timestamp))
                        detailRow("Message", value: currentRecord.message)
                        detailRow("Label", value: currentRecord.label)
                        detailRow("Tag", value: currentRecord.tag)
                        detailRow("App Name", value: currentRecord.appName)
                        detailRow("Source", value: currentRecord.source)
                        detailRow("File", value: currentRecord.file)
                        detailRow("Function", value: currentRecord.function)
                        detailRow("Line", value: String(currentRecord.line))
                        
                        metadataTable
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical)
            }
            .navigationTitle("Log Detail")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 16) {
                        Button {
                            Task { await loadPrevious() }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!canGoPrevious || isLoading)
                        
                        Button {
                            Task { await loadNext() }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!canGoNext || isLoading)
                    }
                }
            }
            .task {
                await checkNavigationAvailability()
            }
        }
    }
    
    private func checkNavigationAvailability() async {
        async let previousTask = manager.getPreviousLog(from: currentRecord.id)
        async let nextTask = manager.getNextLog(from: currentRecord.id)
        
        if let _ = try? await previousTask {
            canGoPrevious = true
        }
        if let _ = try? await nextTask {
            canGoNext = true
        }
    }
    
    private func loadPrevious() async {
        guard canGoPrevious, !isLoading else { return }
        isLoading = true
        
        if let previous = try? await manager.getPreviousLog(from: currentRecord.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentRecord = previous
            }
            isLoading = false
            await checkNavigationAvailability()
        } else {
            canGoPrevious = false
            isLoading = false
        }
    }
    
    private func loadNext() async {
        guard canGoNext, !isLoading else { return }
        isLoading = true
        
        if let next = try? await manager.getNextLog(from: currentRecord.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentRecord = next
            }
            isLoading = false
            await checkNavigationAvailability()
        } else {
            canGoNext = false
            isLoading = false
        }
    }
    
    private var metadataDict: [String: String] {
        guard let data = currentRecord.metadataJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dict = json as? [String: Any] else {
            return [:]
        }
        
        return dict.reduce(into: [:]) { result, pair in
            let key = pair.key
            let value: String
            if let stringValue = pair.value as? String {
                value = stringValue
            } else {
                if let jsonData = try? JSONSerialization.data(withJSONObject: pair.value, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    value = jsonString
                } else {
                    value = String(describing: pair.value)
                }
            }
            result[key] = value
        }
    }
    
    private var metadataTable: some View {
        Group {
            if !metadataDict.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Metadata")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(metadataDict.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(alignment: .top, spacing: 12) {
                                Text(key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                    .lineLimit(1)
                                
                                Text(value)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var levelPillRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Level")
                .font(.caption)
                .foregroundStyle(.secondary)
            LevelPill(level: currentRecord.level, color: style.color(for: currentRecord.level))
        }
    }
    
    private func detailRow(_ title: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(color ?? .primary)
                .textSelection(.enabled)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

#if DEBUG
struct LogDetailView_Previews: PreviewProvider {
    static var previews: some View {
        LogDetailPreviewContainer()
    }
}

private struct LogDetailPreviewContainer: View {
    @State private var manager: SQLiteLogManager?
    @State private var record: LogRecord?
    
    var body: some View {
        Group {
            if let manager = manager, let record = record {
                LogDetailView(
                    manager: manager,
                    currentRecord: record,
                    style: SQLiteLogViewerStyle(),
                    onDismiss: {}
                )
            } else {
                ProgressView("Loading sample log…")
                    .task {
                        await loadPreviewData()
                    }
            }
        }
    }
    
    private func loadPreviewData() async {
        let configuration = SQLiteLoggingConfiguration(
            appName: "LogDetailPreview",
            queueDepth: 64,
            dropPolicy: nil,
            database: .inMemory()
        )
        
        let components = try! SQLiteLoggingSystem.make(configuration: configuration)
        LoggingSystem.bootstrap(components.handlerFactory)
        let mgr = components.manager
        let logger = Logger(label: "Preview")
        
        logger.info("Sample log message for preview", metadata: ["key": "value", "number": "42"])
        logger.debug("Debug log with metadata", metadata: ["debug": "true"])
        
        await mgr.flush()
        
        if let logs = try? await mgr.query(LogQuery(order: .newestFirst)), let firstLog = logs.first {
            await MainActor.run {
                self.manager = mgr
                self.record = firstLog
            }
        }
    }
}
#endif
