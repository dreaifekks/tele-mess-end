import Foundation

enum CoreProfileKind: String, Codable, CaseIterable, Identifiable {
    case remote
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote:
            "Remote"
        case .local:
            "Local"
        }
    }

    var systemImage: String {
        switch self {
        case .remote:
            "network"
        case .local:
            "desktopcomputer"
        }
    }
}

struct CoreProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: CoreProfileKind
    var baseURLString: String
    var authMode: CoreAuthMode
    var localCommand: String
    var localWorkingDirectory: String
    var createdAt: Date
    var updatedAt: Date

    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static var defaultLocal: CoreProfile {
        CoreProfile(
            id: UUID(),
            name: "Local Core",
            kind: .local,
            baseURLString: "http://127.0.0.1:8765",
            authMode: .bearer,
            localCommand: "tele-mess-core run-server --config config.yml",
            localWorkingDirectory: "",
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
