import Foundation

enum CoreAuthMode: String, Codable, CaseIterable, Identifiable {
    case bearer
    case apiToken

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bearer:
            "Bearer"
        case .apiToken:
            "X-Api-Token"
        }
    }
}

enum JSONValue: Codable, Hashable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var description: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            if value.rounded() == value {
                String(Int(value))
            } else {
                String(value)
            }
        case .bool(let value):
            value ? "true" : "false"
        case .object, .array:
            if let data = try? JSONEncoder.pretty.encode(self),
               let string = String(data: data, encoding: .utf8) {
                string
            } else {
                ""
            }
        case .null:
            "null"
        }
    }
}

struct CoreItemsResponse<Item: Decodable>: Decodable {
    var items: [Item]
}

struct CorePage<Item: Decodable>: Decodable {
    var items: [Item]
    var nextCursor: Int?
    var hasMore: Bool?
}

struct CoreWriteResponse<Item: Decodable>: Decodable {
    var item: Item
}

struct CoreAPIErrorPayload: Decodable {
    var error: String?
    var detail: String?
    var message: String?
}

struct CoreState: Codable, Equatable {
    var databaseID: String?
    var schemaVersion: String?
    var lastEventSeq: Int
    var messageCount: Int
    var operationErrorCount: Int?
    var serverTime: String?
    var ok: Bool?
}

struct CoreCapabilities: Decodable, Equatable {
    var mode: String?
    var sync: [String]?
    var management: [String]?
    var authFlow: JSONValue?
}

struct CoreAccount: Decodable, Identifiable, Hashable {
    var source: String
    var accountID: String
    var displayName: String?
    var kind: String?
    var updatedAt: String?
    var rawJSON: JSONValue?
    var authState: String?
    var phone: String?
    var sessionName: String?
    var sessionDir: String?
    var lastError: String?
    var authUpdatedAt: String?
    var authRawJSON: JSONValue?

    var id: String { "\(source):\(accountID)" }
    var title: String { displayName?.isEmpty == false ? displayName! : accountID }
}

struct CoreOrigin: Decodable, Identifiable, Hashable {
    var source: String
    var accountID: String
    var originID: Int
    var topicID: Int
    var originType: String
    var parentOriginID: Int?
    var title: String?
    var username: String?
    var isForum: Bool
    var archivedAt: String?
    var lastMessageAt: String?
    var discoveredAt: String?
    var updatedAt: String?
    var rawJSON: JSONValue?
    var backupPolicy: CoreBackupPolicy?

    var id: String { "\(source):\(accountID):\(originID):\(topicID)" }
    var displayTitle: String { title?.isEmpty == false ? title! : "\(originID)" }
    var isArchived: Bool { archivedAt != nil }
    var isTopic: Bool { topicID != 0 }

    private enum CodingKeys: String, CodingKey {
        case source, accountID, originID, topicID, originType, parentOriginID, title, username
        case isForum, archivedAt, lastMessageAt, discoveredAt, updatedAt, rawJSON, backupPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        accountID = try container.decode(String.self, forKey: .accountID)
        originID = try container.decode(Int.self, forKey: .originID)
        topicID = try container.decodeIfPresent(Int.self, forKey: .topicID) ?? 0
        originType = try container.decode(String.self, forKey: .originType)
        parentOriginID = try container.decodeIfPresent(Int.self, forKey: .parentOriginID)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        isForum = try container.decodeFlexibleBool(forKey: .isForum) ?? false
        archivedAt = try container.decodeIfPresent(String.self, forKey: .archivedAt)
        lastMessageAt = try container.decodeIfPresent(String.self, forKey: .lastMessageAt)
        discoveredAt = try container.decodeIfPresent(String.self, forKey: .discoveredAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        rawJSON = try container.decodeIfPresent(JSONValue.self, forKey: .rawJSON)
        backupPolicy = try container.decodeIfPresent(CoreBackupPolicy.self, forKey: .backupPolicy)
    }
}

struct CoreBackupPolicy: Codable, Identifiable, Hashable {
    var source: String?
    var accountID: String?
    var originID: Int?
    var topicID: Int?
    var enabled: Bool
    var captureText: Bool
    var captureMediaMetadata: Bool
    var downloadMedia: Bool
    var tags: String?
    var updatedAt: String?

    var id: String { "\(source ?? "telegram"):\(accountID ?? ""):\(originID ?? 0):\(topicID ?? 0)" }

    private enum CodingKeys: String, CodingKey {
        case source, accountID, originID, topicID, enabled, captureText, captureMediaMetadata, downloadMedia, tags, updatedAt
    }

    init(
        source: String? = nil,
        accountID: String? = nil,
        originID: Int? = nil,
        topicID: Int? = nil,
        enabled: Bool = false,
        captureText: Bool = true,
        captureMediaMetadata: Bool = true,
        downloadMedia: Bool = false,
        tags: String? = nil,
        updatedAt: String? = nil
    ) {
        self.source = source
        self.accountID = accountID
        self.originID = originID
        self.topicID = topicID
        self.enabled = enabled
        self.captureText = captureText
        self.captureMediaMetadata = captureMediaMetadata
        self.downloadMedia = downloadMedia
        self.tags = tags
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
        originID = try container.decodeIfPresent(Int.self, forKey: .originID)
        topicID = try container.decodeIfPresent(Int.self, forKey: .topicID) ?? 0
        enabled = try container.decodeFlexibleBool(forKey: .enabled) ?? false
        captureText = try container.decodeFlexibleBool(forKey: .captureText) ?? true
        captureMediaMetadata = try container.decodeFlexibleBool(forKey: .captureMediaMetadata) ?? true
        downloadMedia = try container.decodeFlexibleBool(forKey: .downloadMedia) ?? false
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct CoreMessage: Decodable, Identifiable, Hashable {
    var eventSeq: Int?
    var source: String
    var accountID: String
    var chatID: Int
    var messageID: Int
    var topicID: Int?
    var chatTitle: String?
    var senderID: Int?
    var senderName: String?
    var senderUsername: String?
    var sentAt: String?
    var editedAt: String?
    var ingestedAt: String?
    var deletedAt: String?
    var text: String?
    var hasMedia: Bool
    var mediaKind: String?
    var groupedID: String?
    var replyToMessageID: Int?
    var forwardFromID: String?
    var forwardFromName: String?
    var permalink: String?
    var reactionsJSON: JSONValue?
    var rawJSON: JSONValue?
    var version: Int?

    var id: String { "\(source):\(accountID):\(chatID):\(messageID):\(eventSeq ?? 0)" }
    var isDeleted: Bool { deletedAt != nil }
    var displayChat: String { chatTitle?.isEmpty == false ? chatTitle! : "\(chatID)" }
    var displaySender: String { senderName?.isEmpty == false ? senderName! : senderUsername ?? "" }

    private enum CodingKeys: String, CodingKey {
        case eventSeq, source, accountID, chatID, messageID, topicID, chatTitle, senderID, senderName, senderUsername
        case sentAt, editedAt, ingestedAt, deletedAt, text, hasMedia, mediaKind, groupedID, replyToMessageID
        case forwardFromID, forwardFromName, permalink, reactionsJSON, rawJSON, version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventSeq = try container.decodeIfPresent(Int.self, forKey: .eventSeq)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "telegram"
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID) ?? "default"
        chatID = try container.decode(Int.self, forKey: .chatID)
        messageID = try container.decode(Int.self, forKey: .messageID)
        topicID = try container.decodeIfPresent(Int.self, forKey: .topicID)
        chatTitle = try container.decodeIfPresent(String.self, forKey: .chatTitle)
        senderID = try container.decodeIfPresent(Int.self, forKey: .senderID)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
        senderUsername = try container.decodeIfPresent(String.self, forKey: .senderUsername)
        sentAt = try container.decodeIfPresent(String.self, forKey: .sentAt)
        editedAt = try container.decodeIfPresent(String.self, forKey: .editedAt)
        ingestedAt = try container.decodeIfPresent(String.self, forKey: .ingestedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        hasMedia = try container.decodeFlexibleBool(forKey: .hasMedia) ?? false
        mediaKind = try container.decodeIfPresent(String.self, forKey: .mediaKind)
        groupedID = try container.decodeIfPresent(String.self, forKey: .groupedID)
        replyToMessageID = try container.decodeIfPresent(Int.self, forKey: .replyToMessageID)
        forwardFromID = try container.decodeIfPresent(String.self, forKey: .forwardFromID)
        forwardFromName = try container.decodeIfPresent(String.self, forKey: .forwardFromName)
        permalink = try container.decodeIfPresent(String.self, forKey: .permalink)
        reactionsJSON = try container.decodeIfPresent(JSONValue.self, forKey: .reactionsJSON)
        rawJSON = try container.decodeIfPresent(JSONValue.self, forKey: .rawJSON)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
    }
}

struct CoreParticipant: Decodable, Identifiable, Hashable {
    var source: String
    var accountID: String
    var originID: Int
    var userID: Int
    var username: String?
    var displayName: String?
    var isBot: Bool
    var role: String?
    var lastSeenAt: String?
    var updatedAt: String?
    var rawJSON: JSONValue?

    var id: String { "\(source):\(accountID):\(originID):\(userID)" }

    private enum CodingKeys: String, CodingKey {
        case source, accountID, originID, userID, username, displayName, isBot, role, lastSeenAt, updatedAt, rawJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        accountID = try container.decode(String.self, forKey: .accountID)
        originID = try container.decode(Int.self, forKey: .originID)
        userID = try container.decode(Int.self, forKey: .userID)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        isBot = try container.decodeFlexibleBool(forKey: .isBot) ?? false
        role = try container.decodeIfPresent(String.self, forKey: .role)
        lastSeenAt = try container.decodeIfPresent(String.self, forKey: .lastSeenAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        rawJSON = try container.decodeIfPresent(JSONValue.self, forKey: .rawJSON)
    }
}

struct CoreCaptureCursor: Decodable, Identifiable, Hashable {
    var source: String
    var accountID: String
    var originID: Int
    var topicID: Int
    var lastMessageID: Int
    var lastMessageAt: String?
    var lastBackfillAt: String?
    var updatedAt: String?
    var rawJSON: JSONValue?
    var originTitle: String?

    var id: String { "\(source):\(accountID):\(originID):\(topicID)" }
}

struct CoreMediaFile: Decodable, Identifiable, Hashable {
    var source: String
    var accountID: String
    var chatID: Int
    var messageID: Int
    var fileIndex: Int
    var filePath: String
    var mediaKind: String?
    var mimeType: String?
    var fileSize: Int?
    var downloadedAt: String?
    var rawJSON: JSONValue?
    var chatTitle: String?

    var id: String { "\(source):\(accountID):\(chatID):\(messageID):\(fileIndex)" }
}

struct CoreOperationEvent: Decodable, Identifiable, Hashable {
    var id: Int
    var source: String
    var accountID: String
    var operation: String
    var status: String
    var subjectType: String?
    var subjectID: String?
    var errorCode: String?
    var message: String?
    var retryAfter: Int?
    var occurredAt: String?
    var rawJSON: JSONValue?
}

struct DeleteResult: Decodable, Hashable {
    var source: String?
    var accountID: String?
    var originID: Int?
    var topicID: Int?
    var userID: Int?
    var deletedRows: Int?
}

struct ArchiveOriginResult: Decodable, Hashable {
    var source: String
    var accountID: String
    var originID: Int
    var topicID: Int
    var archived: Bool
    var changedRows: Int
}

struct AuthOperationResult: Decodable, Hashable {
    var source: String?
    var accountID: String?
    var authState: String?
    var status: String?
    var phone: String?
    var message: String?
    var lastError: String?
    var code: String?
    var detail: String?
}

struct DiscoveryResult: Decodable, Hashable {
    var source: String?
    var accountID: String?
    var discovered: Int?
    var origins: Int?
    var topics: Int?
    var skippedPrivate: Int?
    var status: String?
    var message: String?
}

struct ParticipantRefreshResult: Decodable, Hashable {
    var source: String?
    var accountID: String?
    var originID: Int?
    var refreshed: Int?
    var status: String?
    var message: String?
}

struct CreateAccountRequest: Encodable {
    var accountID: String
    var displayName: String?
    var phone: String?
    var sessionName: String?
    var sessionDir: String?
    var source: String = "telegram"
}

struct AccountAuthUpdateRequest: Encodable {
    var accountID: String
    var authState: String
    var phone: String?
    var sessionName: String?
    var sessionDir: String?
    var lastError: String?
    var source: String = "telegram"
}

struct AccountAuthStatusRequest: Encodable {
    var accountID: String
    var source: String = "telegram"
}

struct RequestCodeRequest: Encodable {
    var accountID: String
    var phone: String
    var source: String = "telegram"
}

struct SubmitCodeRequest: Encodable {
    var accountID: String
    var phone: String
    var code: String
    var password: String?
    var source: String = "telegram"
}

struct DeleteAccountRequest: Encodable {
    var accountID: String
    var source: String = "telegram"
}

struct DiscoverOriginsRequest: Encodable {
    var accountID: String
    var includeTopics: Bool = true
    var includePrivate: Bool = false
    var topicLimit: Int = 500
    var source: String = "telegram"
}

struct ArchiveOriginRequest: Encodable {
    var accountID: String
    var originID: Int
    var topicID: Int = 0
    var archived: Bool
    var source: String = "telegram"
}

struct DeleteOriginRequest: Encodable {
    var accountID: String
    var originID: Int
    var topicID: Int = 0
    var source: String = "telegram"
}

struct BackupPolicyRequest: Encodable {
    var accountID: String
    var originID: Int
    var topicID: Int = 0
    var enabled: Bool
    var captureText: Bool
    var captureMediaMetadata: Bool
    var downloadMedia: Bool
    var tags: String?
    var source: String = "telegram"
}

struct DeleteBackupPolicyRequest: Encodable {
    var accountID: String
    var originID: Int
    var topicID: Int = 0
    var source: String = "telegram"
}

struct RefreshParticipantsRequest: Encodable {
    var accountID: String
    var originID: Int
    var limit: Int = 500
    var source: String = "telegram"
}

extension KeyedDecodingContainer {
    func decodeFlexibleBool(forKey key: Key) throws -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

extension JSONEncoder {
    static var core: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var core: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
