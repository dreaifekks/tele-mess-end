import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case accounts
    case origins
    case messages
    case messagePoints
    case media
    case summaries
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
        case .messagePoints:
            "Message Points"
        case .media:
            "Media"
        case .summaries:
            "Daily Summary"
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
        case .messagePoints:
            "list.bullet.rectangle"
        case .media:
            "photo.on.rectangle"
        case .summaries:
            "calendar.badge.clock"
        case .diagnostics:
            "stethoscope"
        }
    }

    var requiredEndpointPath: String? {
        switch self {
        case .dashboard:
            nil
        case .accounts:
            "/manage/accounts"
        case .origins:
            "/manage/origins"
        case .messages:
            "/sync/messages"
        case .messagePoints:
            "/manage/daily-message-points"
        case .media:
            "/sync/media-files"
        case .summaries:
            "/manage/daily-summary-records"
        case .diagnostics:
            "/manage/operation-events"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case core
    case summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core:
            "Core Settings"
        case .summary:
            "Summary Settings"
        }
    }

    var label: String {
        switch self {
        case .core:
            "Core"
        case .summary:
            "Summary"
        }
    }

    var systemImage: String {
        switch self {
        case .core:
            "server.rack"
        case .summary:
            "text.badge.star"
        }
    }
}
