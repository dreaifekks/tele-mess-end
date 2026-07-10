import AppKit
import QuickLookUI
import SwiftUI

struct MediaView: View {
    @Bindable var model: AppModel
    @State private var selection: CoreMediaFile.ID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                filters

                if model.mediaFiles.isEmpty {
                    EmptyStateView(title: "No media files", detail: "Media records matching the current filters appear here.", systemImage: "photo.on.rectangle")
                } else {
                    MediaManagementTable(files: model.mediaFiles, selection: $selection)
                }
            }
            .padding(20)
            .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            MediaDetailPanel(model: model, file: selectedFile)
                .id(selectedFile?.id ?? "none")
                .frame(width: 420)
                .frame(maxHeight: .infinity)
                .padding(.leading, 12)
        }
        .navigationTitle("Media")
        .disabled(model.isLoading)
        .task(id: model.sessionRevision) {
            selection = nil
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Account", text: $model.mediaAccountFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Chat ID", text: $model.mediaChatIDFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                TextField("Message ID", text: $model.mediaMessageIDFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                Button {
                    Task { await model.loadMediaFiles() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                Button {
                    model.mediaAccountFilter = ""
                    model.mediaChatIDFilter = ""
                    model.mediaMessageIDFilter = ""
                    Task { await model.loadMediaFiles() }
                } label: {
                    Label("Clear", systemImage: "line.3.horizontal.decrease.circle")
                }
                Spacer()
                Text("\(model.mediaFiles.count) files")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedFile: CoreMediaFile? {
        guard let selection else { return nil }
        return model.mediaFiles.first { $0.id == selection }
    }
}

private struct MediaManagementTable: View {
    var files: [CoreMediaFile]
    @Binding var selection: CoreMediaFile.ID?
    @State private var lastClickedFileID: CoreMediaFile.ID?

    var body: some View {
        Table(files, selection: $selection) {
            TableColumn("Downloaded") { file in
                mediaCell(file) {
                    Text(DisplayFormat.shortDateTime(file.downloadedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn("Account") { file in
                mediaCell(file) {
                    Text(file.accountID)
                }
            }
                .width(min: 90, ideal: 120)

            TableColumn("Chat") { file in
                mediaCell(file) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.displayTitle)
                            .lineLimit(1)
                        Text("\(file.chatID) / \(file.messageID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Kind") { file in
                mediaCell(file) {
                    Text(file.mediaKind ?? file.previewKind ?? "")
                }
            }
            .width(min: 80, ideal: 110)

            TableColumn("Size") { file in
                mediaCell(file) {
                    Text(file.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "")
                }
            }
            .width(min: 80, ideal: 110)

            TableColumn("Location") { file in
                mediaCell(file) {
                    Text(file.filePath ?? file.bestURLString ?? "")
                        .lineLimit(1)
                }
            }
        }
        .onChange(of: selection) {
            if selection == nil {
                lastClickedFileID = nil
            }
        }
    }

    private func mediaCell<Content: View>(_ file: CoreMediaFile, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if selection == file.id, lastClickedFileID == file.id {
                    selection = nil
                    lastClickedFileID = nil
                } else {
                    selection = file.id
                    lastClickedFileID = file.id
                }
            }
    }
}

private struct MediaDetailPanel: View {
    @Bindable var model: AppModel
    var file: CoreMediaFile?
    @State private var previewState: MediaPreviewState = .sealed

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let file {
                Text(file.suggestedFilename)
                    .font(.headline)
                    .lineLimit(2)

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow { Text("Account").foregroundStyle(.secondary); Text(file.accountID) }
                    GridRow { Text("Chat").foregroundStyle(.secondary); Text("\(file.chatID)") }
                    GridRow { Text("Message").foregroundStyle(.secondary); Text("\(file.messageID)") }
                    GridRow { Text("Index").foregroundStyle(.secondary); Text("\(file.fileIndex)") }
                    GridRow { Text("Type").foregroundStyle(.secondary); Text(file.contentType ?? file.mimeType ?? file.mediaKind ?? "") }
                    GridRow { Text("Size").foregroundStyle(.secondary); Text(file.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "") }
                }
                .font(.callout)

                HStack {
                    Button {
                        Task { await model.openMediaFile(file) }
                    } label: {
                        Label("Open", systemImage: "arrow.down.circle")
                    }
                    if let urlString = file.bestURLString, !urlString.isEmpty {
                        Button {
                            copyURL(urlString)
                        } label: {
                            Label("Copy URL", systemImage: "link")
                        }
                    }
                }

                MediaPreviewPanel(file: file, state: previewState) {
                    Task { await loadPreview(for: file) }
                } reload: {
                    Task { await loadPreview(for: file) }
                } hide: {
                    previewState = .sealed
                }
            } else {
                EmptyStateView(title: "Select media", detail: "Pick a file to inspect metadata or open content.", systemImage: "photo")
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private func loadPreview(for file: CoreMediaFile) async {
        guard MediaPreviewSupport.supports(file) else {
            previewState = .unsupported("This file type cannot be previewed.")
            return
        }

        previewState = .loading
        do {
            let data = try await model.fetchMediaContent(file)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TeleMessEndMediaPreviews", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.suggestedFilename)
            try data.write(to: url, options: .atomic)
            previewState = .ready(url)
        } catch {
            previewState = .failed(error.localizedDescription)
        }
    }

    private func copyURL(_ urlString: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        model.statusMessage = "Media URL copied"
        model.lastError = nil
    }
}

private enum MediaPreviewState {
    case sealed
    case loading
    case ready(URL)
    case unsupported(String)
    case failed(String)
}

private struct MediaPreviewPanel: View {
    var file: CoreMediaFile
    var state: MediaPreviewState
    var reveal: () -> Void
    var reload: () -> Void
    var hide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                if case .ready = state {
                    Button {
                        reload()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    Button {
                        hide()
                    } label: {
                        Label("Hide", systemImage: "eye.slash")
                    }
                }
            }

            previewBody
                .frame(maxWidth: .infinity, minHeight: 260)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        switch state {
        case .sealed:
            Button {
                reveal()
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 42, weight: .medium))
                    Text("Preview \(file.mediaKind ?? file.previewKind ?? "media")")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        case .loading:
            ProgressView("Loading preview")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let url):
            QuickLookFilePreview(url: url)
        case .unsupported(let message):
            EmptyStateView(title: "Preview unavailable", detail: message, systemImage: "eye.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyStateView(title: "Preview failed", detail: message, systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct QuickLookFilePreview: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
        view?.autostarts = true
        view?.shouldCloseWithWindow = false
        view?.previewItem = url as NSURL
        return view ?? QLPreviewView()
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
    }
}

private enum MediaPreviewSupport {
    static func supports(_ file: CoreMediaFile) -> Bool {
        let hint = [
            file.contentType,
            file.mimeType,
            file.mediaKind,
            file.previewKind,
            file.filePath,
            file.suggestedFilename
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if hint.contains("image") || hint.contains("photo") {
            return true
        }
        if hint.contains("video") || hint.contains("movie") {
            return true
        }
        if hint.contains("audio") || hint.contains("voice") {
            return true
        }
        if hint.contains("pdf") {
            return true
        }

        let supportedExtensions: Set<String> = [
            "jpg", "jpeg", "png", "gif", "heic", "webp",
            "mp4", "mov", "m4v",
            "mp3", "m4a", "aac", "wav",
            "pdf"
        ]
        return supportedExtensions.contains(URL(fileURLWithPath: file.suggestedFilename).pathExtension.lowercased())
    }
}
