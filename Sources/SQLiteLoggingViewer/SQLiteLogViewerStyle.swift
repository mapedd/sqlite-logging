import Logging
import SwiftUI

public struct SQLiteLogViewerStyle {
    public var logFont: Font
    public var levelColors: [Logger.Level: Color]

    public init(
        logFont: Font = .system(size: 12, design: .monospaced),
        levelColors: [Logger.Level: Color] = SQLiteLogViewerStyle.defaultLevelColors
    ) {
        self.logFont = logFont
        self.levelColors = levelColors
    }

    public static let defaultLevelColors: [Logger.Level: Color] = [
        .critical: .purple,
        .error: .red,
        .warning: .orange,
        .debug: .black,
        .info: .gray,
        .notice: .gray,
        .trace: .green,
    ]

    public func color(for level: Logger.Level) -> Color {
        levelColors[level] ?? .primary
    }
}
