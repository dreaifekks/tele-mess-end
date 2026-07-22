import Darwin
import Foundation
import Security

struct LocalCoreProcessCommand: Equatable {
    var executableURL: URL
    var arguments: [String]
    var currentDirectoryURL: URL?
    var environment: [String: String]
}

struct LocalCoreWorkspaceStatus: Equatable {
    var workspaceDirectory: URL
    var configurationFileURL: URL
    var workspaceExists: Bool
    var configurationExists: Bool
    var configurationIsReadable: Bool

    var isReadyForLaunch: Bool {
        workspaceExists && configurationExists && configurationIsReadable
    }
}

struct LocalCoreBootstrapConfiguration: Equatable {
    var accountID: String
    var apiID: Int
    var apiHash: String
    var sessionName: String
    var timezone: String

    init(
        accountID: String,
        apiID: Int,
        apiHash: String,
        sessionName: String = "tele_mess_core",
        timezone: String = "Asia/Tokyo"
    ) {
        self.accountID = accountID
        self.apiID = apiID
        self.apiHash = apiHash
        self.sessionName = sessionName
        self.timezone = timezone
    }
}

struct LocalCoreBootstrapResult: Equatable {
    var workspaceDirectory: URL
    var configurationFileURL: URL
    var serverToken: String
}

enum LocalCoreRuntimeSupportError: LocalizedError, Equatable {
    case invalidVersion(String)
    case invalidWorkspaceDirectory(String)
    case uvExecutableNotFound
    case managedExecutableMissing(URL)
    case configurationAlreadyExists(URL)
    case invalidAccountID
    case invalidAPIID
    case invalidAPIHash
    case invalidSessionName
    case invalidTimezone(String)
    case secureRandomGenerationFailed(Int32)
    case configurationWriteFailed(URL, Int32)

    var errorDescription: String? {
        switch self {
        case .invalidVersion:
            "The managed Core version is invalid."
        case .invalidWorkspaceDirectory(let value):
            "The local Core workspace must be an absolute path after expanding '~': \(value)"
        case .uvExecutableNotFound:
            "uv was not found. Install uv or add its executable directory to PATH."
        case .managedExecutableMissing(let url):
            "The managed tele-mess-core executable is missing at \(url.path)."
        case .configurationAlreadyExists(let url):
            "A local Core configuration already exists at \(url.path)."
        case .invalidAccountID:
            "The Telegram account ID must not be empty or contain control characters."
        case .invalidAPIID:
            "The Telegram API ID must be greater than zero."
        case .invalidAPIHash:
            "The Telegram API hash must not be empty."
        case .invalidSessionName:
            "The Telegram session name must be a safe file name."
        case .invalidTimezone(let value):
            "The Telegram timezone is invalid: \(value)"
        case .secureRandomGenerationFailed(let status):
            "Could not generate the local Core API token (status \(status))."
        case .configurationWriteFailed(let url, let code):
            "Could not securely create \(url.path) (errno \(code))."
        }
    }
}

struct ManagedLocalCoreRuntime {
    static let distributionName = "tele-mess-core"
    static let executableName = "tele-mess-core"

    let version: String
    let workspaceDirectory: URL
    let applicationSupportDirectory: URL
    let runtimeRootDirectory: URL
    let versionDirectory: URL
    let uvToolDirectory: URL
    let uvBinDirectory: URL
    let uvCacheDirectory: URL
    let managedCoreExecutableURL: URL
    let installedVersionMarkerURL: URL

    private let fileManager: FileManager
    private let baseEnvironment: [String: String]
    private let homeDirectory: URL

    init(
        profile: CoreProfile,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupportDirectory: URL? = nil,
        homeDirectory: URL? = nil
    ) throws {
        let resolvedHomeDirectory = (homeDirectory ?? fileManager.homeDirectoryForCurrentUser)
            .standardizedFileURL
        let version = profile.localCoreVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidVersion(version) else {
            throw LocalCoreRuntimeSupportError.invalidVersion(profile.localCoreVersion)
        }

        let workspaceDirectory = try Self.resolveWorkspaceDirectory(
            profile.localWorkspaceDirectory,
            homeDirectory: resolvedHomeDirectory
        )
        let supportRoot = (
            applicationSupportDirectory
                ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? resolvedHomeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
        ).standardizedFileURL
        let appSupport = supportRoot.appendingPathComponent("TeleMessEnd", isDirectory: true)
        let runtimeRoot = appSupport.appendingPathComponent("CoreRuntime", isDirectory: true)
        let versionDirectory = runtimeRoot
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(Self.sanitizedVersionDirectoryName(version), isDirectory: true)
        let toolDirectory = versionDirectory.appendingPathComponent("tools", isDirectory: true)
        let binDirectory = versionDirectory.appendingPathComponent("bin", isDirectory: true)
        let cacheDirectory = runtimeRoot.appendingPathComponent("cache", isDirectory: true)

        self.version = version
        self.workspaceDirectory = workspaceDirectory
        self.applicationSupportDirectory = appSupport
        runtimeRootDirectory = runtimeRoot
        self.versionDirectory = versionDirectory
        uvToolDirectory = toolDirectory
        uvBinDirectory = binDirectory
        uvCacheDirectory = cacheDirectory
        managedCoreExecutableURL = binDirectory.appendingPathComponent(Self.executableName, isDirectory: false)
        installedVersionMarkerURL = versionDirectory.appendingPathComponent("installed-version", isDirectory: false)
        self.fileManager = fileManager
        baseEnvironment = environment
        self.homeDirectory = resolvedHomeDirectory
    }

    func prepareDirectories() throws {
        try createSecureDirectory(applicationSupportDirectory)
        try createSecureDirectory(runtimeRootDirectory)
        try createSecureDirectory(runtimeRootDirectory.appendingPathComponent("versions", isDirectory: true))
        try createSecureDirectory(versionDirectory)
        try createSecureDirectory(uvToolDirectory)
        try createSecureDirectory(uvBinDirectory)
        try createSecureDirectory(uvCacheDirectory)
    }

    func locateUVExecutable() -> URL? {
        var candidates: [URL] = []
        for key in ["TELE_MESS_END_UV_EXECUTABLE", "UV_EXECUTABLE"] {
            if let rawValue = baseEnvironment[key],
               let url = executableURL(from: rawValue) {
                candidates.append(url)
            }
        }

        if let path = baseEnvironment["PATH"] {
            for component in path.split(separator: ":", omittingEmptySubsequences: true) {
                let directory = expandedURL(for: String(component))
                candidates.append(directory.appendingPathComponent("uv", isDirectory: false))
            }
        }

        candidates.append(contentsOf: [
            homeDirectory
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("uv", isDirectory: false),
            URL(fileURLWithPath: "/opt/homebrew/bin/uv", isDirectory: false),
            URL(fileURLWithPath: "/usr/local/bin/uv", isDirectory: false),
        ])

        var seen = Set<String>()
        return candidates.first { candidate in
            let path = candidate.standardizedFileURL.path
            guard seen.insert(path).inserted else { return false }
            return fileManager.isExecutableFile(atPath: path)
        }?.standardizedFileURL
    }

    func installCommand(force: Bool) throws -> LocalCoreProcessCommand {
        guard let uvExecutableURL = locateUVExecutable() else {
            throw LocalCoreRuntimeSupportError.uvExecutableNotFound
        }
        var arguments = ["tool", "install"]
        if force {
            arguments.append("--force")
        }
        arguments.append(contentsOf: [
            "--no-config",
            "--default-index",
            "https://pypi.org/simple",
            "\(Self.distributionName)==\(version)",
        ])
        return LocalCoreProcessCommand(
            executableURL: uvExecutableURL,
            arguments: arguments,
            currentDirectoryURL: nil,
            environment: installEnvironment(uvExecutableURL: uvExecutableURL)
        )
    }

    func runCommand() -> LocalCoreProcessCommand {
        LocalCoreProcessCommand(
            executableURL: managedCoreExecutableURL,
            arguments: [
                "run-local",
                "--workspace",
                workspaceDirectory.path,
                "--web",
            ],
            currentDirectoryURL: nil,
            environment: runtimeEnvironment()
        )
    }

    var installedVersion: String? {
        guard let data = fileManager.contents(atPath: installedVersionMarkerURL.path),
              let rawValue = String(data: data, encoding: .utf8) else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var isInstalled: Bool {
        installedVersion == version
            && fileManager.isExecutableFile(atPath: managedCoreExecutableURL.path)
    }

    func markInstalled() throws {
        guard fileManager.isExecutableFile(atPath: managedCoreExecutableURL.path) else {
            throw LocalCoreRuntimeSupportError.managedExecutableMissing(managedCoreExecutableURL)
        }
        try prepareDirectories()
        let data = Data("\(version)\n".utf8)
        try data.write(to: installedVersionMarkerURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: installedVersionMarkerURL.path
        )
    }

    func invalidateInstalledVersionMarker() throws {
        guard fileManager.fileExists(atPath: installedVersionMarkerURL.path) else { return }
        try fileManager.removeItem(at: installedVersionMarkerURL)
    }

    func workspaceStatus() -> LocalCoreWorkspaceStatus {
        let configURL = workspaceDirectory.appendingPathComponent("config.yml", isDirectory: false)
        var workspaceIsDirectory = ObjCBool(false)
        let workspaceExists = fileManager.fileExists(
            atPath: workspaceDirectory.path,
            isDirectory: &workspaceIsDirectory
        ) && workspaceIsDirectory.boolValue
        var configIsDirectory = ObjCBool(false)
        let configExists = fileManager.fileExists(
            atPath: configURL.path,
            isDirectory: &configIsDirectory
        ) && !configIsDirectory.boolValue
        return LocalCoreWorkspaceStatus(
            workspaceDirectory: workspaceDirectory,
            configurationFileURL: configURL,
            workspaceExists: workspaceExists,
            configurationExists: configExists,
            configurationIsReadable: configExists && fileManager.isReadableFile(atPath: configURL.path)
        )
    }

    func bootstrapConfiguration(
        _ input: LocalCoreBootstrapConfiguration
    ) throws -> LocalCoreBootstrapResult {
        let accountID = input.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiHash = input.apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = input.sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let timezone = input.timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty,
              !accountID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw LocalCoreRuntimeSupportError.invalidAccountID
        }
        guard input.apiID > 0 else {
            throw LocalCoreRuntimeSupportError.invalidAPIID
        }
        guard !apiHash.isEmpty else {
            throw LocalCoreRuntimeSupportError.invalidAPIHash
        }
        guard Self.isSafeSessionName(sessionName) else {
            throw LocalCoreRuntimeSupportError.invalidSessionName
        }
        guard TimeZone(identifier: timezone) != nil else {
            throw LocalCoreRuntimeSupportError.invalidTimezone(timezone)
        }

        let configURL = workspaceDirectory.appendingPathComponent("config.yml", isDirectory: false)
        if fileManager.fileExists(atPath: configURL.path) {
            throw LocalCoreRuntimeSupportError.configurationAlreadyExists(configURL)
        }

        try createSecureDirectory(workspaceDirectory)
        try createSecureDirectory(workspaceDirectory.appendingPathComponent("data", isDirectory: true))
        try createSecureDirectory(
            workspaceDirectory
                .appendingPathComponent("data", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        )
        try createSecureDirectory(workspaceDirectory.appendingPathComponent("logs", isDirectory: true))

        let serverToken = try Self.generateServerToken()
        let config = """
        storage:
          data_dir: "./data"
          database: "./data/archive.db"

        telegram:
          accounts:
            - account_id: \(try Self.yamlQuoted(accountID))
              api_id: \(input.apiID)
              api_hash: \(try Self.yamlQuoted(apiHash))
              session_name: \(try Self.yamlQuoted(sessionName))
              session_dir: "./data/sessions"
              timezone: \(try Self.yamlQuoted(timezone))

        server:
          host: "127.0.0.1"
          port: 8765
          token: \(try Self.yamlQuoted(serverToken))
          allow_unauthenticated_localhost: false

        logging:
          level: "INFO"
          file: "./logs/tele-mess-core.log"
        """ + "\n"
        try writeConfigurationExclusively(Data(config.utf8), to: configURL)
        return LocalCoreBootstrapResult(
            workspaceDirectory: workspaceDirectory,
            configurationFileURL: configURL,
            serverToken: serverToken
        )
    }

    private func runtimeEnvironment(uvExecutableURL: URL? = nil) -> [String: String] {
        var environment = baseEnvironment
        environment["UV_TOOL_DIR"] = uvToolDirectory.path
        environment["UV_TOOL_BIN_DIR"] = uvBinDirectory.path
        environment["UV_CACHE_DIR"] = uvCacheDirectory.path
        if environment["HOME", default: ""].isEmpty {
            environment["HOME"] = homeDirectory.path
        }

        var pathComponents = [uvBinDirectory.path]
        if let uvExecutableURL {
            pathComponents.append(uvExecutableURL.deletingLastPathComponent().path)
        }
        pathComponents.append(
            homeDirectory
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .path
        )
        pathComponents.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ])
        if let existingPath = baseEnvironment["PATH"] {
            pathComponents.append(contentsOf: existingPath.split(separator: ":").map(String.init))
        }
        pathComponents.append(contentsOf: [
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ])

        var seen = Set<String>()
        environment["PATH"] = pathComponents
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }

    private func installEnvironment(uvExecutableURL: URL) -> [String: String] {
        var environment = runtimeEnvironment(uvExecutableURL: uvExecutableURL)
        let allowedUVVariables = Set([
            "UV_TOOL_DIR",
            "UV_TOOL_BIN_DIR",
            "UV_CACHE_DIR",
        ])
        for key in Array(environment.keys) where key.hasPrefix("UV_") {
            if !allowedUVVariables.contains(key) {
                environment.removeValue(forKey: key)
            }
        }
        for key in [
            "PIP_CONFIG_FILE",
            "PIP_INDEX_URL",
            "PIP_EXTRA_INDEX_URL",
            "PIP_FIND_LINKS",
            "PIP_NO_INDEX",
            "PIP_CONSTRAINT",
            "PIP_REQUIREMENT",
        ] {
            environment.removeValue(forKey: key)
        }
        return environment
    }

    private func createSecureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: url.path
        )
    }

    private func executableURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let url = expandedURL(for: value)
        guard (url.path as NSString).isAbsolutePath else { return nil }
        return url.standardizedFileURL
    }

    private func expandedURL(for rawValue: String) -> URL {
        if rawValue == "~" {
            return homeDirectory
        }
        if rawValue.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(rawValue.dropFirst(2)))
        }
        return URL(fileURLWithPath: rawValue, isDirectory: true)
    }

    private func writeConfigurationExclusively(_ data: Data, to url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        let temporaryURL = parentDirectory.appendingPathComponent(
            ".config.yml.\(UUID().uuidString).tmp",
            isDirectory: false
        )
        var descriptor = Darwin.open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw LocalCoreRuntimeSupportError.configurationWriteFailed(url, errno)
        }

        var published = false
        defer {
            if descriptor >= 0 { Darwin.close(descriptor) }
            if !published { Darwin.unlink(temporaryURL.path) }
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    throw LocalCoreRuntimeSupportError.configurationWriteFailed(url, errno)
                }
                if written == 0 {
                    throw LocalCoreRuntimeSupportError.configurationWriteFailed(url, EIO)
                }
                offset += written
            }
        }
        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            throw LocalCoreRuntimeSupportError.configurationWriteFailed(url, errno)
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw LocalCoreRuntimeSupportError.configurationWriteFailed(url, errno)
        }
        guard Darwin.close(descriptor) == 0 else {
            descriptor = -1
            throw LocalCoreRuntimeSupportError.configurationWriteFailed(url, errno)
        }
        descriptor = -1

        let renameStatus = temporaryURL.path.withCString { sourcePath in
            url.path.withCString { destinationPath in
                Darwin.renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameStatus == 0 else {
            let code = errno
            if code == EEXIST {
                throw LocalCoreRuntimeSupportError.configurationAlreadyExists(url)
            }
            throw LocalCoreRuntimeSupportError.configurationWriteFailed(url, code)
        }
        published = true

        // The file itself is already durable and atomically visible. Syncing
        // the directory is a best-effort durability barrier because some
        // user-selected filesystems reject directory fsync with EINVAL.
        let directoryDescriptor = Darwin.open(parentDirectory.path, O_RDONLY)
        if directoryDescriptor >= 0 {
            _ = Darwin.fsync(directoryDescriptor)
            Darwin.close(directoryDescriptor)
        }
    }

    private static func resolveWorkspaceDirectory(
        _ rawValue: String,
        homeDirectory: URL
    ) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = value.isEmpty ? CoreProfile.defaultLocalWorkspaceDirectory : value
        let expanded: String
        if fallback == "~" {
            expanded = homeDirectory.path
        } else if fallback.hasPrefix("~/") {
            expanded = homeDirectory
                .appendingPathComponent(String(fallback.dropFirst(2)), isDirectory: true)
                .path
        } else if fallback.hasPrefix("~") {
            throw LocalCoreRuntimeSupportError.invalidWorkspaceDirectory(rawValue)
        } else {
            expanded = fallback
        }
        guard (expanded as NSString).isAbsolutePath else {
            throw LocalCoreRuntimeSupportError.invalidWorkspaceDirectory(rawValue)
        }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    private static func isValidVersion(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".!+_-"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func sanitizedVersionDirectoryName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".!+_-"))
        return String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        })
    }

    private static func isSafeSessionName(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func generateServerToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw LocalCoreRuntimeSupportError.secureRandomGenerationFailed(status)
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func yamlQuoted(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw LocalCoreRuntimeSupportError.configurationWriteFailed(
                URL(fileURLWithPath: "config.yml"),
                EILSEQ
            )
        }
        return encoded
    }
}

typealias LocalCoreRuntimeSupport = ManagedLocalCoreRuntime
