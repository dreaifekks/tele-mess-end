import Foundation
import Observation

@MainActor
@Observable
final class CoreProfileStore {
    private(set) var profiles: [CoreProfile] = []
    private(set) var selectedProfileID: UUID?

    private let defaults: UserDefaults
    private let profilesKey = "teleMessEnd.coreProfiles"
    private let selectedKey = "teleMessEnd.selectedProfileID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var selectedProfile: CoreProfile? {
        guard let selectedProfileID else {
            return profiles.first
        }
        return profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    func load() {
        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([CoreProfile].self, from: data),
           !decoded.isEmpty {
            profiles = decoded
        } else {
            profiles = [.defaultLocal]
        }

        if let selected = defaults.string(forKey: selectedKey),
           let id = UUID(uuidString: selected),
           profiles.contains(where: { $0.id == id }) {
            selectedProfileID = id
        } else {
            selectedProfileID = profiles.first?.id
        }
        save()
    }

    func select(_ id: UUID?) {
        if let id, profiles.contains(where: { $0.id == id }) {
            selectedProfileID = id
        } else {
            selectedProfileID = profiles.first?.id
        }
        save()
    }

    func upsert(_ profile: CoreProfile) {
        var updated = profile
        updated.updatedAt = Date()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updated
        } else {
            profiles.append(updated)
        }
        selectedProfileID = updated.id
        save()
    }

    func addRemoteProfile() -> CoreProfile {
        let profile = CoreProfile(
            id: UUID(),
            name: "Remote Core",
            kind: .remote,
            baseURLString: "http://",
            authMode: .bearer,
            localCommand: "",
            localWorkingDirectory: "",
            createdAt: Date(),
            updatedAt: Date()
        )
        profiles.append(profile)
        selectedProfileID = profile.id
        save()
        return profile
    }

    func addLocalProfile() -> CoreProfile {
        let profile = CoreProfile.defaultLocal
        profiles.append(profile)
        selectedProfileID = profile.id
        save()
        return profile
    }

    func deleteSelected() -> CoreProfile? {
        guard let selectedProfileID,
              profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return nil
        }
        let removed = profiles.remove(at: index)
        self.selectedProfileID = profiles.first?.id
        save()
        return removed
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        defaults.set(selectedProfileID?.uuidString, forKey: selectedKey)
    }
}
