import Logging
import SwiftUI

struct LevelPill: View {
    let level: Logger.Level
    let color: Color
    
    var body: some View {
        Text(level.rawValue.uppercased())
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#if DEBUG
struct LevelPill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ForEach(Logger.Level.allCases, id: \.self) { level in
                HStack {
                    LevelPill(level: level, color: previewColor(for: level))
                    Spacer()
                }
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
    
    private static func previewColor(for level: Logger.Level) -> Color {
        switch level {
        case .trace:
            return .gray
        case .debug:
            return Color(red: 0.0, green: 0.5, blue: 1.0)
        case .info:
            return Color(red: 0.0, green: 0.8, blue: 0.0)
        case .notice:
            return Color(red: 0.0, green: 0.6, blue: 0.8)
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        case .critical:
            return Color.purple
        }
    }
}
#endif
