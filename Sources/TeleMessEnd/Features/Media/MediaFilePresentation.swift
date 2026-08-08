import Foundation

enum MediaFileType: String, CaseIterable, Identifiable {
    case image
    case video
    case text
    case audio
    case document
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image:
            "Image"
        case .video:
            "Video"
        case .text:
            "Text"
        case .audio:
            "Audio"
        case .document:
            "Document"
        case .other:
            "Other"
        }
    }
}

struct MediaFileListSnapshot {
    var visibleFiles: [CoreMediaFile]
    var returnedCount: Int

    var hasMore: Bool {
        visibleFiles.count < returnedCount
    }

    var remainingCount: Int {
        max(0, returnedCount - visibleFiles.count)
    }
}

struct MediaFileListState: Equatable {
    static let defaultBatchSize = 100

    let batchSize: Int
    private(set) var visibleLimit: Int

    init(batchSize: Int = defaultBatchSize) {
        let batchSize = max(1, batchSize)
        self.batchSize = batchSize
        self.visibleLimit = batchSize
    }

    mutating func showMore(returnedCount: Int) {
        guard visibleLimit < returnedCount else { return }
        visibleLimit = min(returnedCount, visibleLimit + batchSize)
    }

    mutating func resetVisibleLimit() {
        visibleLimit = batchSize
    }

    func snapshot(from returnedFiles: [CoreMediaFile]) -> MediaFileListSnapshot {
        return MediaFileListSnapshot(
            visibleFiles: Array(returnedFiles.prefix(visibleLimit)),
            returnedCount: returnedFiles.count
        )
    }
}

struct MediaFilenameDebounceTicket: Equatable {
    fileprivate var revision: UInt
    var query: String
}

struct MediaFilenameDebounceGate: Equatable {
    private(set) var revision: UInt = 0

    mutating func schedule(query: String) -> MediaFilenameDebounceTicket {
        revision &+= 1
        return MediaFilenameDebounceTicket(revision: revision, query: query)
    }

    mutating func cancelPending() {
        revision &+= 1
    }

    func accepts(_ ticket: MediaFilenameDebounceTicket) -> Bool {
        ticket.revision == revision
    }
}

extension CoreMediaFile {
    var displayType: MediaFileType {
        if let mediaType,
           let type = MediaFileType(rawValue: mediaType.lowercased()) {
            return type
        }
        if let previewKind,
           let type = MediaFileType(hint: previewKind),
           type != .document {
            return type
        }
        for contentHint in [contentType, mimeType].compactMap({ $0 }) {
            if let type = MediaFileType(hint: contentHint) {
                return type
            }
        }
        if let mediaKind,
           let type = MediaFileType(hint: mediaKind),
           type != .document {
            return type
        }
        if let fileExtension, let type = MediaFileType(fileExtension: fileExtension) {
            return type
        }
        if let previewKind, let type = MediaFileType(hint: previewKind) {
            return type
        }
        if let mediaKind, let type = MediaFileType(hint: mediaKind) {
            return type
        }
        return .other
    }
}

private extension MediaFileType {
    init?(hint: String) {
        let hint = hint.lowercased()
        if hint.contains("image") || hint.contains("photo") {
            self = .image
        } else if hint.contains("video") || hint.contains("movie") {
            self = .video
        } else if hint.contains("text") || hint.contains("markdown") || hint.contains("json") ||
                    hint.contains("csv") || hint.contains("html") || hint.contains("xml") ||
                    hint.contains("yaml") {
            self = .text
        } else if hint.contains("audio") || hint.contains("voice") || hint.contains("opus") {
            self = .audio
        } else if hint.contains("pdf") || hint.contains("document") || hint.contains("msword") ||
                    hint.contains("wordprocessingml") || hint.contains("spreadsheetml") ||
                    hint.contains("presentationml") || hint.contains("rtf") {
            self = .document
        } else {
            return nil
        }
    }

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff", "svg":
            self = .image
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "mpg", "mpeg", "ts":
            self = .video
        case "txt", "md", "markdown", "json", "jsonl", "csv", "tsv", "html", "htm", "xml", "yaml", "yml", "log", "srt", "vtt":
            self = .text
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus":
            self = .audio
        case "pdf", "doc", "docx", "rtf", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key":
            self = .document
        default:
            return nil
        }
    }
}
