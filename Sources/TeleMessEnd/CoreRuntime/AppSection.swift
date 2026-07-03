import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case accounts
    case origins
    case messages
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            "Dashboard"
        case .accounts:
            "Accounts"
        case .origins:
            "Origins"
        case .messages:
            "Messages"
        case .diagnostics:
            "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            "gauge.with.dots.needle.bottom.50percent"
        case .accounts:
            "person.2"
        case .origins:
            "rectangle.stack"
        case .messages:
            "bubble.left.and.text.bubble.right"
        case .diagnostics:
            "stethoscope"
        }
    }
}
