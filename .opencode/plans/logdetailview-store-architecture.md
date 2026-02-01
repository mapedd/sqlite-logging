# Implementation Plan: LogDetailView with Navigation Store

## Overview
Create a navigation store object that manages the current log and provides methods to fetch next/previous logs, keeping the view decoupled from the data structure.

## Architecture

### 1. LogDetailStore Protocol/Interface
```swift
protocol LogDetailStore: ObservableObject {
    var currentRecord: LogRecord { get }
    var canGoPrevious: Bool { get }
    var canGoNext: Bool { get }
    
    func previous() async
    func next() async
}
```

### 2. InMemoryLogStore Implementation
For the current use case where we have all records in memory:
```swift
class InMemoryLogStore: LogDetailStore {
    @Published var currentRecord: LogRecord
    let allRecords: [LogRecord]
    
    var canGoPrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }
    
    var canGoNext: Bool {
        guard let index = currentIndex else { return false }
        return index < allRecords.count - 1
    }
    
    private var currentIndex: Int? {
        allRecords.firstIndex { $0.id == currentRecord.id }
    }
    
    init(initialRecord: LogRecord, allRecords: [LogRecord]) {
        self.currentRecord = initialRecord
        self.allRecords = allRecords
    }
    
    func previous() async {
        guard let index = currentIndex, index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentRecord = allRecords[index - 1]
        }
    }
    
    func next() async {
        guard let index = currentIndex, index < allRecords.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentRecord = allRecords[index + 1]
        }
    }
}
```

### 3. Updated LogDetailView
```swift
struct LogDetailView<Store: LogDetailStore>: View {
    @StateObject var store: Store
    let style: SQLiteLogViewerStyle
    let onNavigate: (LogRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // All detail rows using store.currentRecord
                    detailRow("UUID", value: store.currentRecord.uuid.uuidString)
                    detailRow("Level", value: store.currentRecord.level.rawValue.uppercased(), 
                             color: style.color(for: store.currentRecord.level))
                    // ... other rows
                    
                    // Metadata table using store.currentRecord.metadataJSON
                    metadataTable
                }
                .padding(.horizontal)
            }
            .navigationTitle("Log Detail")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 16) {
                        Button { 
                            Task {
                                await store.previous()
                                onNavigate(store.currentRecord)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!store.canGoPrevious)
                        
                        Button {
                            Task {
                                await store.next()
                                onNavigate(store.currentRecord)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!store.canGoNext)
                    }
                }
            }
        }
    }
    
    private var metadataTable: some View {
        // Parse metadataJSON into [String: String]
        // Display in 2-column LazyVGrid
    }
}
```

### 4. Updated Parent View (SQLiteLogViewer)
```swift
.sheet(item: $selectedLogRecord) { record in
    let store = InMemoryLogStore(
        initialRecord: record, 
        allRecords: recordsFromState
    )
    LogDetailView(
        store: store,
        style: style,
        onNavigate: { newRecord in
            // Optional: Track navigation or sync external state
        }
    )
}
```

## Key Benefits

1. **Separation of Concerns**: View only knows about `currentRecord`, not the entire array
2. **Testability**: Easy to mock the store for testing
3. **Flexibility**: Can implement different stores (e.g., database-backed store for lazy loading)
4. **Animation**: Store handles the state update with animation
5. **Async Support**: Store methods are async, allowing for future database fetches

## Future Extensibility

This architecture supports:
- **Database-backed store**: Fetch next/previous from SQLite on demand instead of keeping all in memory
- **Caching**: Store can implement smart caching of nearby records
- **Prefetching**: Store can prefetch next records while user is viewing current

## Files to Modify

1. `/Users/mapedd/Documents/sqlite-logging/Sources/SQLiteLoggingViewer/SQLiteLogViewer.swift`
   - Add LogDetailStore protocol
   - Add InMemoryLogStore class
   - Update LogDetailView to use generic Store parameter
   - Update sheet presentation to create store

## Questions for Clarification

1. Should the store be a class or struct? (Class allows @Published for ObservableObject)
2. Do we need the onNavigate callback if the store manages everything internally?
3. Should we support async/await in the store methods for future database integration?

## Build Verification
Run `swift build` to ensure no compilation errors.
