# Implementation Plan: LogDetailView Improvements

## Overview
Update the LogDetailView to support smooth in-place navigation between logs and display metadata as a formatted key-value table.

## Changes Required

### 1. State-Based Navigation (No Sheet Dismissal)
**Current Issue:** When navigating between logs, the parent view updates `selectedLogRecord` which causes the entire sheet to dismiss and re-appear.

**Solution:** Change `record` from `let` to `@State` and update it directly within the view.

**Implementation:**
```swift
// Change from:
let record: LogRecord

// To:
@State var record: LogRecord
```

Update all references to use `self.record`:
- `allRecords.firstIndex { $0.id == self.record.id }`
- All `detailRow()` calls referencing `record`

Update navigation buttons:
```swift
Button {
    if let prev = previousRecord {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.record = prev
            onNavigate(prev)  // Notify parent for tracking
        }
    }
} label: {
    Image(systemName: "chevron.left")
}
```

### 2. Metadata Table View
**Current Issue:** Metadata is displayed as raw JSON string.

**Solution:** Parse JSON into key-value pairs and display in a 2-column grid layout.

**Implementation:**

Add a computed property to parse metadata:
```swift
private var metadataDict: [String: String] {
    guard let data = record.metadataJSON.data(using: .utf8),
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
            // For nested objects/arrays, format as JSON
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
```

Replace the simple metadata row with a table:
```swift
if !metadataDict.isEmpty {
    VStack(alignment: .leading, spacing: 8) {
        Text("Metadata")
            .font(.caption)
            .foregroundStyle(.secondary)
        
        LazyVGrid(columns: [
            GridItem(.flexible(minimum: 80, maximum: 150), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ], spacing: 8) {
            ForEach(metadataDict.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                Text(key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    .padding(.horizontal)
}
```

## Files to Modify
- `/Users/mapedd/Documents/sqlite-logging/Sources/SQLiteLoggingViewer/SQLiteLogViewer.swift`
  - Lines 472-582: Update LogDetailView struct

## Testing Checklist
- [ ] Navigate between logs using prev/next buttons - sheet should stay open
- [ ] Verify animation is smooth when switching logs
- [ ] Verify metadata displays as key-value table
- [ ] Test with nested metadata objects (should show formatted JSON)
- [ ] Test with simple string metadata values
- [ ] Ensure all other log properties still display correctly

## Build Verification
Run `swift build` to ensure no compilation errors after changes.

## Notes
- The `onNavigate` callback is kept to notify the parent view of navigation events (useful for analytics or tracking)
- Animation duration set to 0.2s for snappy but smooth transitions
- Metadata table uses a 2-column grid with fixed key column width for readability
