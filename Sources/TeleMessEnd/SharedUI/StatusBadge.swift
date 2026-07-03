import SwiftUI

enum StatusBadgeKind {
    case neutral
    case success
    case warning
    case error
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
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch kind {
        case .neutral:
            Color.secondary.opacity(0.12)
        case .success:
            Color.green.opacity(0.14)
        case .warning:
            Color.orange.opacity(0.16)
        case .error:
            Color.red.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch kind {
        case .neutral:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
