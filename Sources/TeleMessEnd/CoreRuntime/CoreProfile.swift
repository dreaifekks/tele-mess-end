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

enum LocalCoreRuntimeMode: String, Codable, CaseIterable, Identifiable {
    case managedPyPI
    case customCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .managedPyPI:
            "Managed PyPI"
        case .customCommand:
            "Custom Command"
        }
    }
}

struct CoreProfile: Identifiable, Codable, Hashable {
    static let defaultManagedLocalCoreVersion = "0.3.0"
    static let defaultLocalWorkspaceDirectory = "~/Library/Application Support/tele-mess-core"
    static let legacyDefaultLocalCommand = "tele-mess-core run-server --config config.yml"

    var id: UUID
    var name: String
    var kind: CoreProfileKind
    var baseURLString: String
    var authMode: CoreAuthMode
    var localCommand: String
    var localWorkingDirectory: String
    var createdAt: Date
    var updatedAt: Date
    var localRuntimeMode: LocalCoreRuntimeMode
    var localCoreVersion: String
    var localWorkspaceDirectory: String

    init(
        id: UUID,
        name: String,
        kind: CoreProfileKind,
        baseURLString: String,
        authMode: CoreAuthMode,
        localCommand: String,
        localWorkingDirectory: String,
        createdAt: Date,
        updatedAt: Date,
        localRuntimeMode: LocalCoreRuntimeMode = .managedPyPI,
        localCoreVersion: String = CoreProfile.defaultManagedLocalCoreVersion,
        localWorkspaceDirectory: String = CoreProfile.defaultLocalWorkspaceDirectory
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURLString = baseURLString
        self.authMode = authMode
        self.localCommand = localCommand
        self.localWorkingDirectory = localWorkingDirectory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.localRuntimeMode = localRuntimeMode
        self.localCoreVersion = localCoreVersion
        self.localWorkspaceDirectory = localWorkspaceDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case baseURLString
        case authMode
        case localCommand
        case localWorkingDirectory
        case createdAt
        case updatedAt
        case localRuntimeMode
        case localCoreVersion
        case localWorkspaceDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedKind = (try? container.decode(CoreProfileKind.self, forKey: .kind)) ?? .remote
        let now = Date()

        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decode(String.self, forKey: .name))
            ?? (decodedKind == .local ? "Local Core" : "Remote Core")
        kind = decodedKind
        baseURLString = (try? container.decode(String.self, forKey: .baseURLString))
            ?? (decodedKind == .local ? "http://127.0.0.1:8765" : "http://")
        authMode = (try? container.decode(CoreAuthMode.self, forKey: .authMode)) ?? .bearer
        localCommand = (try? container.decode(String.self, forKey: .localCommand)) ?? ""
        localWorkingDirectory = (try? container.decode(String.self, forKey: .localWorkingDirectory)) ?? ""
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? now
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        if let decodedMode = try? container.decode(LocalCoreRuntimeMode.self, forKey: .localRuntimeMode) {
            localRuntimeMode = decodedMode
        } else {
            let command = localCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            localRuntimeMode = decodedKind == .local
                && !command.isEmpty
                && command != Self.legacyDefaultLocalCommand
                ? .customCommand
                : .managedPyPI
        }

        let decodedVersion = ((try? container.decode(String.self, forKey: .localCoreVersion)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        localCoreVersion = decodedVersion.isEmpty ? Self.defaultManagedLocalCoreVersion : decodedVersion

        let decodedWorkspace = ((try? container.decode(String.self, forKey: .localWorkspaceDirectory)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyWorkingDirectory = localWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !decodedWorkspace.isEmpty {
            localWorkspaceDirectory = decodedWorkspace
        } else if decodedKind == .local,
                  localRuntimeMode == .managedPyPI,
                  !legacyWorkingDirectory.isEmpty {
            // The legacy default command resolved config.yml from its working
            // directory. Foundation Process resolved a relative working path
            // against the app process's cwd, so persist that same absolute
            // location for the explicit v0.3 workspace contract.
            let expandedLegacyDirectory = (legacyWorkingDirectory as NSString).expandingTildeInPath
            localWorkspaceDirectory = URL(
                fileURLWithPath: expandedLegacyDirectory,
                isDirectory: true
            ).standardizedFileURL.path
        } else {
            localWorkspaceDirectory = Self.defaultLocalWorkspaceDirectory
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(baseURLString, forKey: .baseURLString)
        try container.encode(authMode, forKey: .authMode)
        try container.encode(localCommand, forKey: .localCommand)
        try container.encode(localWorkingDirectory, forKey: .localWorkingDirectory)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(localRuntimeMode, forKey: .localRuntimeMode)
        try container.encode(localCoreVersion, forKey: .localCoreVersion)
        try container.encode(localWorkspaceDirectory, forKey: .localWorkspaceDirectory)
    }

    var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var localWorkspaceURL: URL? {
        let value = localWorkspaceDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = value.isEmpty ? Self.defaultLocalWorkspaceDirectory : value
        let expanded = (source as NSString).expandingTildeInPath
        guard (expanded as NSString).isAbsolutePath else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    static var defaultLocal: CoreProfile {
        CoreProfile(
            id: UUID(),
            name: "Local Core",
            kind: .local,
            baseURLString: "http://127.0.0.1:8765",
            authMode: .bearer,
            localCommand: "",
            localWorkingDirectory: "",
            createdAt: Date(),
            updatedAt: Date(),
            localRuntimeMode: .managedPyPI,
            localCoreVersion: defaultManagedLocalCoreVersion,
            localWorkspaceDirectory: defaultLocalWorkspaceDirectory
        )
    }
}
