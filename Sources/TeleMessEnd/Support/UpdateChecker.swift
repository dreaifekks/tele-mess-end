import Foundation
import Observation

func compareVersions(_ lhs: String, _ rhs: String) throws -> ComparisonResult {
    func components(_ version: String) throws -> [Int] {
        let version = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let numericPart = version.components(separatedBy: "-")[0]
        return try numericPart.components(separatedBy: ".").map { component in
            guard let number = Int(component) else { throw VersionError.invalidComponent }
            return number
        }
    }

    let left = try components(lhs)
    let right = try components(rhs)
    for index in 0..<max(3, left.count, right.count) {
        let leftValue = index < left.count ? left[index] : 0
        let rightValue = index < right.count ? right[index] : 0
        if leftValue < rightValue { return .orderedAscending }
        if leftValue > rightValue { return .orderedDescending }
    }
    return .orderedSame
}

private enum VersionError: Error {
    case invalidComponent
}

struct AvailableUpdate {
    var version: String
    var url: URL
}

@MainActor
@Observable
final class UpdateChecker {
    private(set) var availableUpdate: AvailableUpdate?
    private(set) var isChecking = false
    var showsUpToDate = false

    private let defaults: UserDefaults
    private let currentVersion: String?
    private let runtimeLogger: AppRuntimeLogger
    private let fetch: (URLRequest) async throws -> Data
    private let lastCheckKey = "teleMessEnd.updateLastCheckedAt"
    private let skippedVersionKey = "teleMessEnd.updateSkippedVersion"

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        runtimeLogger: AppRuntimeLogger = AppLog.runtime,
        fetch: @escaping (URLRequest) async throws -> Data = { request in
            try await URLSession.shared.data(for: request).0
        }
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.runtimeLogger = runtimeLogger
        self.fetch = fetch
    }

    func check(manually: Bool = false) async {
        guard !isChecking else { return }
        if !manually,
           let lastCheck = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 {
            return
        }
        guard let currentVersion else {
            runtimeLogger.warning("Update check skipped: bundle version is missing")
            return
        }

        isChecking = true
        showsUpToDate = false
        defaults.set(Date(), forKey: lastCheckKey)
        defer { isChecking = false }

        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/dreaifekks/tele-mess-end/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let release = try JSONDecoder().decode(Release.self, from: await fetch(request))
            let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            if try compareVersions(version, currentVersion) == .orderedDescending {
                let skippedVersion = defaults.string(forKey: skippedVersionKey)
                let wasSkipped = try skippedVersion.map { try compareVersions(version, $0) != .orderedDescending } ?? false
                availableUpdate = wasSkipped ? nil : AvailableUpdate(version: version, url: release.htmlURL)
            } else {
                availableUpdate = nil
                showsUpToDate = manually
            }
        } catch {
            runtimeLogger.warning("Update check failed: \(error.localizedDescription)")
        }
    }

    func skip() {
        guard let availableUpdate else { return }
        defaults.set(availableUpdate.version, forKey: skippedVersionKey)
        self.availableUpdate = nil
    }

    private struct Release: Decodable {
        var tagName: String
        var htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
