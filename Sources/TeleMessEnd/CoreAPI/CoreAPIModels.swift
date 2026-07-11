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

    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct CoreWriteResponse<Item: Decodable>: Decodable {
    var item: Item
}

struct CoreAPIManifest: Decodable, Equatable {
    var name: String?
    var contractVersion: String
    var contractHash: String
    var openAPIURL: String?
    var markdownURL: String?
    var agentDoc: String?
    var endpoints: [JSONValue]
    var schemas: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case name
        case contractVersion = "contract_version"
        case contractHash = "contract_hash"
        case openAPIURL = "openapi_url"
        case markdownURL = "markdown_url"
        case agentDoc = "agent_doc"
        case endpoints
        case schemas
    }
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

    var schemaVersionText: String {
        schemaVersion ?? "-"
    }

    private enum CodingKeys: String, CodingKey {
        case databaseID = "database_id"
        case schemaVersion = "schema_version"
        case lastEventSeq = "last_event_seq"
        case messageCount = "message_count"
        case operationErrorCount = "operation_error_count"
        case serverTime = "server_time"
        case ok
    }

    init(
        databaseID: String?,
        schemaVersion: String?,
        lastEventSeq: Int,
        messageCount: Int,
        operationErrorCount: Int?,
        serverTime: String?,
        ok: Bool?
    ) {
        self.databaseID = databaseID
        self.schemaVersion = schemaVersion
        self.lastEventSeq = lastEventSeq
        self.messageCount = messageCount
        self.operationErrorCount = operationErrorCount
        self.serverTime = serverTime
        self.ok = ok
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        databaseID = try container.decodeIfPresent(String.self, forKey: .databaseID)
        if let text = try? container.decodeIfPresent(String.self, forKey: .schemaVersion) {
            schemaVersion = text
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .schemaVersion) {
            schemaVersion = String(number)
        } else {
            schemaVersion = nil
        }
        lastEventSeq = try container.decode(Int.self, forKey: .lastEventSeq)
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        operationErrorCount = try container.decodeIfPresent(Int.self, forKey: .operationErrorCount)
        serverTime = try container.decodeIfPresent(String.self, forKey: .serverTime)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(databaseID, forKey: .databaseID)
        try container.encodeIfPresent(schemaVersion, forKey: .schemaVersion)
        try container.encode(lastEventSeq, forKey: .lastEventSeq)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encodeIfPresent(operationErrorCount, forKey: .operationErrorCount)
        try container.encodeIfPresent(serverTime, forKey: .serverTime)
        try container.encodeIfPresent(ok, forKey: .ok)
    }
}

struct CoreCapabilities: Decodable, Equatable {
    var mode: String?
    var sync: [String]?
    var management: [String]?
    var authFlow: JSONValue?
    var apiContract: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case mode
        case sync
        case management
        case authFlow = "auth_flow"
        case apiContract = "api_contract"
    }
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

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case displayName = "display_name"
        case kind
        case updatedAt = "updated_at"
        case rawJSON = "raw_json"
        case authState = "auth_state"
        case phone
        case sessionName = "session_name"
        case sessionDir = "session_dir"
        case lastError = "last_error"
        case authUpdatedAt = "auth_updated_at"
        case authRawJSON = "auth_raw_json"
    }
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
    var parentTitle: String?
    var important: Bool
    var rawJSON: JSONValue?
    var backupPolicy: CoreBackupPolicy?

    var id: String { "\(source):\(accountID):\(originID):\(topicID)" }
    var displayTitle: String { title?.isEmpty == false ? title! : "\(originID)" }
    var isArchived: Bool { archivedAt != nil }
    var isTopic: Bool { topicID != 0 }
    var backupSortValue: String { backupPolicy?.enabled == true ? "0" : "1" }
    var tagsSortValue: String { backupPolicy?.tags ?? "" }
    var lastMessageSortValue: String { lastMessageAt ?? "" }

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case originID = "origin_id"
        case topicID = "topic_id"
        case originType = "origin_type"
        case parentOriginID = "parent_origin_id"
        case title
        case username
        case isForum = "is_forum"
        case archivedAt = "archived_at"
        case lastMessageAt = "last_message_at"
        case discoveredAt = "discovered_at"
        case updatedAt = "updated_at"
        case parentTitle = "parent_title"
        case important
        case rawJSON = "raw_json"
        case backupPolicy = "backup_policy"
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
        parentTitle = try container.decodeIfPresent(String.self, forKey: .parentTitle)
        important = try container.decodeFlexibleBool(forKey: .important) ?? false
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
        case source
        case accountID = "account_id"
        case originID = "origin_id"
        case topicID = "topic_id"
        case enabled
        case captureText = "capture_text"
        case captureMediaMetadata = "capture_media_metadata"
        case downloadMedia = "download_media"
        case tags
        case updatedAt = "updated_at"
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
    var mediaCount: Int?
    var mediaFiles: [CoreMediaFile]?
    var groupedID: String?
    var replyToMessageID: Int?
    var forwardFromID: String?
    var forwardFromName: String?
    var permalink: String?
    var originTitle: String?
    var reactionsJSON: JSONValue?
    var rawJSON: JSONValue?
    var version: Int?

    var id: String { "\(source):\(accountID):\(chatID):\(messageID):\(eventSeq ?? 0)" }
    var isDeleted: Bool { deletedAt != nil }
    var displayChat: String { chatTitle?.isEmpty == false ? chatTitle! : "\(chatID)" }
    var displaySender: String { senderName?.isEmpty == false ? senderName! : senderUsername ?? "" }
    var telegramDeepLink: URL? {
        if let permalink,
           let url = URL(string: permalink),
           url.host?.localizedCaseInsensitiveContains("t.me") == true {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.first == "c", components.count >= 3 {
                return URL(string: "tg://privatepost?channel=\(components[1])&post=\(components[2])")
            }
            if components.count >= 2 {
                return URL(string: "tg://resolve?domain=\(components[0])&post=\(components[1])")
            }
        }

        let absoluteChatID = String(abs(chatID))
        let channelID = absoluteChatID.hasPrefix("100") ? String(absoluteChatID.dropFirst(3)) : absoluteChatID
        return URL(string: "tg://privatepost?channel=\(channelID)&post=\(messageID)")
    }

    private enum CodingKeys: String, CodingKey {
        case eventSeq = "event_seq"
        case source
        case accountID = "account_id"
        case chatID = "chat_id"
        case messageID = "message_id"
        case topicID = "topic_id"
        case chatTitle = "chat_title"
        case senderID = "sender_id"
        case senderName = "sender_name"
        case senderUsername = "sender_username"
        case sentAt = "sent_at"
        case editedAt = "edited_at"
        case ingestedAt = "ingested_at"
        case deletedAt = "deleted_at"
        case text
        case hasMedia = "has_media"
        case mediaKind = "media_kind"
        case mediaCount = "media_count"
        case mediaFiles = "media_files"
        case groupedID = "grouped_id"
        case replyToMessageID = "reply_to_message_id"
        case forwardFromID = "forward_from_id"
        case forwardFromName = "forward_from_name"
        case permalink
        case originTitle = "origin_title"
        case reactionsJSON = "reactions_json"
        case rawJSON = "raw_json"
        case version
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
        mediaCount = try container.decodeIfPresent(Int.self, forKey: .mediaCount)
        mediaFiles = try container.decodeIfPresent([CoreMediaFile].self, forKey: .mediaFiles)
        groupedID = try container.decodeIfPresent(String.self, forKey: .groupedID)
        replyToMessageID = try container.decodeIfPresent(Int.self, forKey: .replyToMessageID)
        forwardFromID = try container.decodeIfPresent(String.self, forKey: .forwardFromID)
        forwardFromName = try container.decodeIfPresent(String.self, forKey: .forwardFromName)
        permalink = try container.decodeIfPresent(String.self, forKey: .permalink)
        originTitle = try container.decodeIfPresent(String.self, forKey: .originTitle)
        reactionsJSON = try container.decodeIfPresent(JSONValue.self, forKey: .reactionsJSON)
        rawJSON = try container.decodeIfPresent(JSONValue.self, forKey: .rawJSON)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
    }
}

struct CoreEvent: Decodable, Identifiable, Hashable {
    var seq: Int
    var source: String
    var accountID: String
    var eventType: String
    var chatID: Int?
    var messageID: Int?
    var eventAt: String?
    var payloadJSON: JSONValue?

    var id: Int { seq }

    private enum CodingKeys: String, CodingKey {
        case seq
        case source
        case accountID = "account_id"
        case eventType = "event_type"
        case chatID = "chat_id"
        case messageID = "message_id"
        case eventAt = "event_at"
        case payloadJSON = "payload_json"
    }
}

struct CoreChat: Decodable, Identifiable, Hashable {
    var source: String
    var accountID: String
    var chatID: Int
    var title: String?
    var username: String?
    var kind: String?
    var updatedAt: String?
    var rawJSON: JSONValue?

    var id: String { "\(source):\(accountID):\(chatID)" }
    var displayTitle: String { title?.isEmpty == false ? title! : "\(chatID)" }

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case chatID = "chat_id"
        case title
        case username
        case kind
        case updatedAt = "updated_at"
        case rawJSON = "raw_json"
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
        case source
        case accountID = "account_id"
        case originID = "origin_id"
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case isBot = "is_bot"
        case role
        case lastSeenAt = "last_seen_at"
        case updatedAt = "updated_at"
        case rawJSON = "raw_json"
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
    var lastMessageID: Int?
    var lastMessageAt: String?
    var lastBackfillAt: String?
    var updatedAt: String?
    var rawJSON: JSONValue?
    var originTitle: String?

    var id: String { "\(source):\(accountID):\(originID):\(topicID)" }

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case originID = "origin_id"
        case topicID = "topic_id"
        case lastMessageID = "last_message_id"
        case lastMessageAt = "last_message_at"
        case lastBackfillAt = "last_backfill_at"
        case updatedAt = "updated_at"
        case rawJSON = "raw_json"
        case originTitle = "origin_title"
    }
}

struct CoreMediaFile: Decodable, Identifiable, Hashable {
    var source: String
    var accountID: String
    var chatID: Int
    var messageID: Int
    var fileIndex: Int
    var filePath: String?
    var mediaKind: String?
    var mimeType: String?
    var fileSize: Int?
    var downloadedAt: String?
    var rawJSON: JSONValue?
    var chatTitle: String?
    var originTitle: String?
    var contentType: String?
    var previewKind: String?
    var accessURL: String?
    var downloadURL: String?

    var id: String { "\(source):\(accountID):\(chatID):\(messageID):\(fileIndex)" }
    var displayTitle: String { originTitle ?? chatTitle ?? "\(chatID)" }
    var bestURLString: String? { downloadURL ?? accessURL }
    var suggestedFilename: String {
        if let filePath, !filePath.isEmpty {
            let name = URL(fileURLWithPath: filePath).lastPathComponent
            if !name.isEmpty {
                return name
            }
        }
        let ext: String
        switch (mimeType ?? contentType ?? mediaKind ?? "").lowercased() {
        case let value where value.contains("jpeg") || value.contains("jpg"):
            ext = "jpg"
        case let value where value.contains("png"):
            ext = "png"
        case let value where value.contains("gif"):
            ext = "gif"
        case let value where value.contains("mp4") || value.contains("video"):
            ext = "mp4"
        case let value where value.contains("pdf"):
            ext = "pdf"
        default:
            ext = "bin"
        }
        return "media-\(chatID)-\(messageID)-\(fileIndex).\(ext)"
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case chatID = "chat_id"
        case messageID = "message_id"
        case fileIndex = "file_index"
        case filePath = "file_path"
        case mediaKind = "media_kind"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case downloadedAt = "downloaded_at"
        case rawJSON = "raw_json"
        case chatTitle = "chat_title"
        case originTitle = "origin_title"
        case contentType = "content_type"
        case previewKind = "preview_kind"
        case accessURL = "access_url"
        case downloadURL = "download_url"
    }
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
    var error: JSONValue?
    var errorType: String?
    var authState: String?
    var subject: JSONValue?
    var subjectLabel: String?
    var rawJSON: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case accountID = "account_id"
        case operation
        case status
        case subjectType = "subject_type"
        case subjectID = "subject_id"
        case errorCode = "error_code"
        case message
        case retryAfter = "retry_after"
        case occurredAt = "occurred_at"
        case error
        case errorType = "error_type"
        case authState = "auth_state"
        case subject
        case subjectLabel = "subject_label"
        case rawJSON = "raw_json"
    }
}

struct DailyPackageSchedule: Decodable, Hashable {
    var enabled: Bool
    var timeOfDay: String
    var timezone: String
    var scope: JSONValue
    var delivery: DailySummaryDeliveryConfig?
    var deliveryWasProvided: Bool
    var systemManager: String
    var installed: Bool
    var lastInstalledAt: String?
    var lastError: String?
    var updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case enabled
        case timeOfDay = "time_of_day"
        case timezone
        case scope
        case delivery
        case systemManager = "system_manager"
        case installed
        case lastInstalledAt = "last_installed_at"
        case lastError = "last_error"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        timeOfDay = try container.decode(String.self, forKey: .timeOfDay)
        timezone = try container.decode(String.self, forKey: .timezone)
        scope = try container.decodeIfPresent(JSONValue.self, forKey: .scope) ?? .object([:])
        deliveryWasProvided = container.contains(.delivery)
        delivery = try container.decodeIfPresent(DailySummaryDeliveryConfig.self, forKey: .delivery)
        systemManager = try container.decodeIfPresent(String.self, forKey: .systemManager) ?? "systemd-user"
        installed = try container.decodeIfPresent(Bool.self, forKey: .installed) ?? false
        lastInstalledAt = try container.decodeIfPresent(String.self, forKey: .lastInstalledAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct DailySummaryDeliveryConfig: Codable, Hashable {
    var enabled: Bool
    var accountID: String
    var originID: Int?
    var topicID: Int

    private enum CodingKeys: String, CodingKey {
        case enabled
        case accountID = "account_id"
        case originID = "origin_id"
        case topicID = "topic_id"
    }

    init(
        enabled: Bool = false,
        accountID: String = "",
        originID: Int? = nil,
        topicID: Int = 0
    ) {
        self.enabled = enabled
        self.accountID = accountID
        self.originID = originID
        self.topicID = topicID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID) ?? ""
        originID = try container.decodeIfPresent(Int.self, forKey: .originID)
        topicID = try container.decodeIfPresent(Int.self, forKey: .topicID) ?? 0
    }
}

struct DailyPackageScheduleInput: Encodable {
    var enabled: Bool
    var timeOfDay: String
    var timezone: String
    var scope: JSONValue?
    var systemManager: String
    var activateSystemd: Bool
    var delivery: DailySummaryDeliveryConfig? = nil
}

struct DailyPackageRun: Decodable, Identifiable, Hashable {
    var runID: String
    var status: String
    var date: String
    var timezone: String
    var scope: JSONValue?
    var outputDir: String?
    var packageJSONPath: String?
    var packageMDPath: String?
    var originCount: Int?
    var messageCount: Int?
    var mediaCount: Int?
    var importantOriginCount: Int?
    var progressCurrent: Int?
    var progressTotal: Int?
    var progressLabel: String?
    var progress: JSONValue?
    var error: String?
    var startedAt: String?
    var finishedAt: String?

    var id: String { runID }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
        case date
        case timezone
        case scope
        case outputDir = "output_dir"
        case packageJSONPath = "package_json_path"
        case packageMDPath = "package_md_path"
        case originCount = "origin_count"
        case messageCount = "message_count"
        case mediaCount = "media_count"
        case importantOriginCount = "important_origin_count"
        case progressCurrent = "progress_current"
        case progressTotal = "progress_total"
        case progressLabel = "progress_label"
        case progress
        case error
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

struct DailyPackageRunInput: Encodable {
    var date: String?
    var timezone: String?
    var scope: JSONValue?
    var accountID: String?
    var originID: Int?
    var topicID: Int?
    var tags: String?
    var tagGroups: [String]?
}

struct DailySummaryRun: Decodable, Identifiable, Hashable {
    var runID: String
    var status: String
    var packageRunID: String?
    var date: String?
    var timezone: String?
    var scope: JSONValue?
    var outputDir: String?
    var summaryPath: String?
    var provider: String?
    var originCount: Int?
    var groupCount: Int?
    var imageCount: Int?
    var progressCurrent: Int?
    var progressTotal: Int?
    var progressLabel: String?
    var progress: JSONValue?
    var error: String?
    var startedAt: String?
    var finishedAt: String?

    var id: String { runID }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
        case packageRunID = "package_run_id"
        case date
        case timezone
        case scope
        case outputDir = "output_dir"
        case summaryPath = "summary_path"
        case provider
        case originCount = "origin_count"
        case groupCount = "group_count"
        case imageCount = "image_count"
        case progressCurrent = "progress_current"
        case progressTotal = "progress_total"
        case progressLabel = "progress_label"
        case progress
        case error
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

struct DailySummaryJob: Decodable, Identifiable, Hashable {
    var jobID: String
    var status: String
    var packageRunID: String?
    var summaryRunID: String?
    var date: String?
    var timezone: String?
    var scope: JSONValue?
    var provider: String?
    var progressCurrent: Int?
    var progressTotal: Int?
    var progressLabel: String?
    var progress: JSONValue?
    var error: String?
    var startedAt: String?
    var updatedAt: String?
    var finishedAt: String?
    var cancelRequestedAt: String?

    var id: String { jobID }

    var isActive: Bool {
        !["completed", "failed", "cancelled", "canceled"].contains(status.lowercased())
    }

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case packageRunID = "package_run_id"
        case summaryRunID = "summary_run_id"
        case date
        case timezone
        case scope
        case provider
        case progressCurrent = "progress_current"
        case progressTotal = "progress_total"
        case progressLabel = "progress_label"
        case progress
        case error
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case finishedAt = "finished_at"
        case cancelRequestedAt = "cancel_requested_at"
    }
}

struct DailySummaryJobCancelInput: Encodable {
    var jobID: String

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
    }
}

struct DailySummaryRunInput: Encodable {
    var packageRunID: String?
    var date: String?
    var timezone: String?
    var scope: JSONValue?
    var accountID: String?
    var originID: Int?
    var topicID: Int?
    var tags: String?
    var tagGroups: [String]?
    var background: Bool
}

struct DailyMessagePoint: Decodable, Identifiable, Hashable {
    var pointID: String
    var runID: String
    var packageRunID: String
    var date: String
    var timezone: String
    var source: String
    var accountID: String
    var originID: Int
    var topicID: Int
    var originTitle: String?
    var messageID: Int?
    var occurredAt: String
    var tags: [String]
    var tagsCSV: String?
    var content: String
    var telegramDeeplink: String?
    var permalink: String?
    var importanceScore: Int
    var importanceReason: String?
    var originImportant: Bool
    var sourceRefs: [JSONValue]
    var provider: String?
    var runStatus: String?
    var jobStatus: String?
    var createdAt: String?
    var updatedAt: String?

    var id: String { pointID }

    private enum CodingKeys: String, CodingKey {
        case pointID = "point_id"
        case runID = "run_id"
        case packageRunID = "package_run_id"
        case date
        case timezone
        case source
        case accountID = "account_id"
        case originID = "origin_id"
        case topicID = "topic_id"
        case originTitle = "origin_title"
        case messageID = "message_id"
        case occurredAt = "occurred_at"
        case tags
        case tagsCSV = "tags_csv"
        case content
        case telegramDeeplink = "telegram_deeplink"
        case permalink
        case importanceScore = "importance_score"
        case importanceReason = "importance_reason"
        case originImportant = "origin_important"
        case sourceRefs = "source_refs"
        case provider
        case runStatus = "run_status"
        case jobStatus = "job_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DailySummaryRecord: Decodable, Identifiable, Hashable {
    var summaryID: String
    var runID: String
    var packageRunID: String?
    var date: String?
    var timezone: String?
    var scope: JSONValue?
    var tags: [String]?
    var tagsCSV: String?
    var important: Bool?
    var recordType: String
    var provider: String?
    var title: String?
    var contentPreview: String
    var contentMD: String?
    var contentJSON: JSONValue?
    var summaryPath: String?
    var originCount: Int?
    var groupCount: Int?
    var imageCount: Int?
    var contentLength: Int?
    var deleted: Bool?
    var deletedAt: String?
    var createdAt: String?
    var updatedAt: String?

    var id: String { summaryID }

    private enum CodingKeys: String, CodingKey {
        case summaryID = "summary_id"
        case runID = "run_id"
        case packageRunID = "package_run_id"
        case date
        case timezone
        case scope
        case tags
        case tagsCSV = "tags_csv"
        case important
        case recordType = "record_type"
        case provider
        case title
        case contentPreview = "content_preview"
        case contentMD = "content_md"
        case contentJSON = "content_json"
        case summaryPath = "summary_path"
        case originCount = "origin_count"
        case groupCount = "group_count"
        case imageCount = "image_count"
        case contentLength = "content_length"
        case deleted
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension DailySummaryRecord {
    var recordTypeSortValue: String {
        recordType
    }

    var recordTypeDisplayName: String {
        switch recordType {
        case "important_daily":
            "Important Daily"
        case "point_daily":
            "Message Points"
        case "important_origin":
            "Important Origin"
        case "tag_group":
            "Tag Group"
        case "final":
            "Final"
        default:
            recordType
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    var titleSortValue: String {
        title ?? summaryID
    }

    var dateSortValue: String {
        date ?? ""
    }

    var tagsSortValue: String {
        tagsCSV ?? tags?.joined(separator: ", ") ?? ""
    }

    var providerSortValue: String {
        provider ?? ""
    }

    var updatedSortValue: String {
        updatedAt ?? createdAt ?? date ?? ""
    }
}

struct DailySummaryRecordDeleteInput: Encodable {
    var summaryID: String?
    var ids: [String]?
    var summaryIDs: [String]?
    var deleted: Bool

    private enum CodingKeys: String, CodingKey {
        case summaryID = "summary_id"
        case ids
        case summaryIDs = "summary_ids"
        case deleted
    }
}

struct DailySummaryRecordDeleteResult: Decodable, Hashable {
    var summaryIDs: [String]
    var deleted: Bool
    var changedRows: Int

    private enum CodingKeys: String, CodingKey {
        case summaryIDs = "summary_ids"
        case deleted
        case changedRows = "changed_rows"
    }
}

struct OperationEventDeleteResult: Decodable, Hashable {
    var ids: [Int]
    var deleted: Int
}

struct DeleteResult: Decodable, Hashable {
    var source: String?
    var accountID: String?
    var originID: Int?
    var topicID: Int?
    var userID: Int?
    var deletedRows: Int?

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case originID = "origin_id"
        case topicID = "topic_id"
        case userID = "user_id"
        case deletedRows = "deleted_rows"
    }
}

struct ArchiveOriginResult: Decodable, Hashable {
    var source: String
    var accountID: String
    var originID: Int
    var topicID: Int
    var archived: Bool
    var changedRows: Int

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case originID = "origin_id"
        case topicID = "topic_id"
        case archived
        case changedRows = "changed_rows"
    }
}

struct AuthOperationResult: Decodable, Hashable {
    var source: String?
    var accountID: String?
    var authorized: Bool?
    var authState: String?
    var status: String?
    var phone: String?
    var message: String?
    var requiresPassword: Bool?
    var phoneCodeHash: String?
    var lastError: String?
    var code: String?
    var detail: String?

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case authorized
        case authState = "auth_state"
        case status
        case phone
        case message
        case requiresPassword = "requires_password"
        case phoneCodeHash = "phone_code_hash"
        case lastError = "last_error"
        case code
        case detail
    }
}

struct DiscoveryResult: Decodable, Hashable {
    var source: String?
    var accountID: String?
    var authorized: Bool?
    var discovered: Int?
    var origins: Int?
    var topics: Int?
    var privateSkipped: Int?
    var errors: [JSONValue]?
    var topicsTruncated: Bool?
    var topicLimit: Int?
    var includePrivate: Bool?
    var status: String?
    var message: String?

    var skippedPrivate: Int? { privateSkipped }

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case authorized
        case discovered
        case origins
        case topics
        case privateSkipped = "private_skipped"
        case errors
        case topicsTruncated = "topics_truncated"
        case topicLimit = "topic_limit"
        case includePrivate = "include_private"
        case status
        case message
    }
}

struct ParticipantRefreshResult: Decodable, Hashable {
    var source: String?
    var accountID: String?
    var originID: Int?
    var authorized: Bool?
    var participants: Int?
    var errors: [JSONValue]?
    var participantsTruncated: Bool?
    var limit: Int?
    var status: String?
    var message: String?

    var refreshed: Int? { participants }

    private enum CodingKeys: String, CodingKey {
        case source
        case accountID = "account_id"
        case originID = "origin_id"
        case authorized
        case participants
        case errors
        case participantsTruncated = "participants_truncated"
        case limit
        case status
        case message
    }
}

struct CreateAccountRequest: Encodable {
    var accountID: String
    var displayName: String?
    var kind: String? = nil
    var authState: String? = nil
    var phone: String?
    var sessionName: String?
    var sessionDir: String?
    var source: String = "telegram"
}

struct AccountAuthUpdateRequest: Encodable {
    var accountID: String
    var authState: String
    var status: String?
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

struct DeleteOperationEventRequest: Encodable {
    var id: Int?
    var ids: [Int]? = nil
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

struct OriginImportantRequest: Encodable {
    var accountID: String
    var originID: Int
    var topicID: Int = 0
    var important: Bool
    var source: String = "telegram"
}

struct DeleteOriginRequest: Encodable {
    var accountID: String
    var originID: Int
    var topicID: Int = 0
    var source: String = "telegram"
}

struct OriginUpdateRequest: Encodable {
    var accountID: String
    var originID: Int
    var topicID: Int = 0
    var originType: String
    var parentOriginID: Int?
    var title: String?
    var username: String?
    var isForum: Bool?
    var lastMessageAt: String?
    var important: Bool?
    var source: String = "telegram"

    init(origin: CoreOrigin, important: Bool? = nil) {
        accountID = origin.accountID
        originID = origin.originID
        topicID = origin.topicID
        originType = origin.originType
        parentOriginID = origin.parentOriginID
        title = origin.title
        username = origin.username
        isForum = origin.isForum
        lastMessageAt = origin.lastMessageAt
        self.important = important
        source = origin.source
    }
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

struct ParticipantRequest: Encodable {
    var accountID: String
    var originID: Int
    var userID: Int
    var username: String?
    var displayName: String?
    var isBot: Bool?
    var role: String?
    var lastSeenAt: String?
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
        return decoder
    }
}
