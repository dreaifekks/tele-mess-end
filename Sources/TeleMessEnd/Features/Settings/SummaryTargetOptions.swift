import Foundation

struct ScopePickerOption: Identifiable, Hashable {
    var value: String
    var title: String
    var id: String { value }
}

struct SummaryTargetOptions {
    let accounts: [CoreAccount]
    let origins: [CoreOrigin]
    let draft: SummarySettings

    var scopeAccountIDs: [String] {
        Array(Set(accounts.map(\.accountID) + origins.map(\.accountID))).sorted()
    }

    var deliveryAccounts: [ScopePickerOption] {
        scopeAccountIDs.map { accountID in
            if let account = accounts.first(where: { $0.accountID == accountID }),
               account.title != accountID {
                return ScopePickerOption(value: accountID, title: "\(account.title)  \(accountID)")
            }
            return ScopePickerOption(value: accountID, title: accountID)
        }
    }

    var scopeOrigins: [ScopePickerOption] {
        let rows = origins.filter { origin in
            draft.accountID.isEmpty || origin.accountID == draft.accountID
        }
        var grouped: [Int: CoreOrigin] = [:]
        for origin in rows where grouped[origin.originID] == nil || !origin.isTopic {
            grouped[origin.originID] = origin
        }
        return grouped.values
            .sorted(by: compareTitles)
            .map(originOption)
    }

    var scopeTopics: [ScopePickerOption] {
        var seen = Set<String>()
        return origins
            .filter { origin in
                origin.isTopic &&
                    (draft.accountID.isEmpty || origin.accountID == draft.accountID) &&
                    (draft.originID.isEmpty || String(origin.originID) == draft.originID)
            }
            .sorted(by: compareTitles)
            .compactMap { origin in
                let value = String(origin.topicID)
                guard seen.insert(value).inserted else { return nil }
                return ScopePickerOption(value: value, title: "\(origin.displayTitle)  \(origin.topicID)")
            }
    }

    var deliveryOrigins: [ScopePickerOption] {
        let rows = origins.filter { origin in
            draft.deliveryAccountID.isEmpty || origin.accountID == draft.deliveryAccountID
        }
        var grouped: [Int: CoreOrigin] = [:]
        for origin in rows where !origin.isTopic || grouped[origin.originID] == nil {
            grouped[origin.originID] = origin
        }
        return grouped.values
            .sorted(by: compareTitles)
            .map(originOption)
    }

    var deliveryTopics: [ScopePickerOption] {
        origins
            .filter { origin in
                origin.isTopic &&
                    (draft.deliveryAccountID.isEmpty || origin.accountID == draft.deliveryAccountID) &&
                    (draft.deliveryOriginID.isEmpty || String(origin.originID) == draft.deliveryOriginID)
            }
            .sorted(by: compareTitles)
            .map { origin in
                ScopePickerOption(value: String(origin.topicID), title: "\(origin.displayTitle)  \(origin.topicID)")
            }
    }

    var scopeTags: [String] {
        let tags = origins.flatMap { Self.splitTags($0.backupPolicy?.tags ?? "") }
        return Array(Set(tags)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func compareTitles(_ lhs: CoreOrigin, _ rhs: CoreOrigin) -> Bool {
        lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }

    private func originOption(_ origin: CoreOrigin) -> ScopePickerOption {
        ScopePickerOption(value: String(origin.originID), title: "\(origin.displayTitle)  \(origin.originID)")
    }

    private static func splitTags(_ value: String) -> [String] {
        value
            .split { character in
                character == "," || character == ";" || character == " " || character == "\n" || character == "\t"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
