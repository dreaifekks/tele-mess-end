import Foundation

enum OriginBackupFilter: String, CaseIterable, Identifiable {
    case any
    case enabled
    case disabled
    case missingPolicy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any:
            "Any backup"
        case .enabled:
            "Backup on"
        case .disabled:
            "Backup off"
        case .missingPolicy:
            "No policy"
        }
    }
}

enum OriginSort: String, CaseIterable, Identifiable {
    case lastMessageDesc
    case lastMessageAsc
    case titleAsc
    case accountAsc
    case typeAsc
    case backupDesc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastMessageDesc:
            "Last message desc"
        case .lastMessageAsc:
            "Last message asc"
        case .titleAsc:
            "Title A-Z"
        case .accountAsc:
            "Account A-Z"
        case .typeAsc:
            "Type A-Z"
        case .backupDesc:
            "Backup first"
        }
    }
}
