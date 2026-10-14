import SwiftUI

enum StatusBadgeKind {
    case neutral
    case success
    case warning
    case error

    var tint: Color {
        switch self {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

struct StatusBadge: View {
    var text: String
    var kind: StatusBadgeKind = .neutral

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(kind.tint.opacity(0.14))
            .foregroundStyle(kind.tint)
            .clipShape(Capsule())
    }
}
