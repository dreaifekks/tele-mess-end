import AppKit
import QuickLookUI
import SwiftUI

struct MediaView: View {
    @Bindable var model: AppModel
    @State private var selection: CoreMediaFile.ID?
    @State private var listState = MediaFileListState()
    @State private var textFilterResetRevision: UInt = 0
    @State private var mediaReloadTask: Task<Void, Never>?

    var body: some View {
        let snapshot = listState.snapshot(from: model.mediaFiles)
        let rows = snapshot.visibleFiles.map(MediaTableRow.init)
        let visibleFileIDs = Set(rows.map(\.id))
        let selectedFile = selection.flatMap { selectedID in
            snapshot.visibleFiles.first { $0.id == selectedID }
        }

        VStack(alignment: .leading, spacing: 14) {
            filters(snapshot: snapshot).fixedSize(horizontal: false, vertical: true)
            AdaptiveDetailLayout(hasDetail: selectedFile != nil) {
                if model.isMediaQueryPending && snapshot.visibleFiles.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Querying matching media from Core…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if snapshot.visibleFiles.isEmpty {
                    EmptyStateView(
                        title: model.mediaLoadError == nil
                            ? (hasActiveMediaFilters ? "No matching media" : "No media files")
                            : "Media request failed",
                        detail: model.mediaLoadError == nil
                            ? (hasActiveMediaFilters
                                ? "The Core returned no media matching the current server-side filters."
                                : "Downloaded media records appear here.")
                            : model.mediaLoadError ?? "",
                        systemImage: model.mediaLoadError == nil ? "photo.on.rectangle" : "exclamationmark.triangle"
                    )
                } else {
                    MediaManagementTable(rows: rows, selection: $selection)
                }
            } detail: {
                MediaDetailPanel(model: model, file: selectedFile)
                    .id(selectedFile?.id ?? "none")
            }
        }
        .padding(20)
        .navigationTitle("Media")
        .task(id: model.sessionRevision) {
            mediaReloadTask?.cancel()
            resetLocalPresentation()
        }
        .onChange(of: model.mediaFilesRevision) {
            listState.resetVisibleLimit()
        }
        .onChange(of: visibleFileIDs) {
            if let selection, !visibleFileIDs.contains(selection) {
                self.selection = nil
            }
        }
        .onDisappear {
            mediaReloadTask?.cancel()
        }
    }

    private func filters(snapshot: MediaFileListSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DebouncedMediaTextField(
                    prompt: "Search filename",
                    text: Binding(
                        get: { model.mediaFilenameQuery },
                        set: commitFilenameQuery
                    ),
                    resetRevision: $textFilterResetRevision
                )
                .frame(minWidth: 190, idealWidth: 250, maxWidth: 320)
                Picker(
                    "Type",
                    selection: Binding(
                        get: { model.mediaTypeFilter },
                        set: commitMediaType
                    )
                ) {
                    Text("All types").tag("")
                    ForEach(MediaFileType.allCases) { type in
                        Text(type.title).tag(type.rawValue)
                    }
                }
                .frame(width: 155)
                DebouncedMediaTextField(
                    prompt: "Extension",
                    text: Binding(
                        get: { model.mediaFileExtensionFilter },
                        set: commitFileExtension
                    ),
                    resetRevision: $textFilterResetRevision
                )
                .frame(width: 175)
                Spacer()
            }
            MediaCoreFilterControls(
                model: model,
                reload: {
                    scheduleMediaReload()
                },
                clear: {
                    model.clearMediaFilters()
                    resetLocalPresentation()
                    scheduleMediaReload()
                }
            )
            HStack {
                Spacer()
                if model.isMediaQueryPending {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating server results…")
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        snapshot.returnedCount == 500
                            ? "\(snapshot.visibleFiles.count) shown / 500 returned · result cap reached"
                            : "\(snapshot.visibleFiles.count) shown / \(snapshot.returnedCount) returned"
                    )
                    .foregroundStyle(.secondary)
                    .help("The Core applies filename, type, and extension filters before returning at most 500 matching files.")
                }
                if snapshot.hasMore {
                    Button {
                        listState.showMore(returnedCount: snapshot.returnedCount)
                    } label: {
                        Label(
                            "Show \(min(listState.batchSize, snapshot.remainingCount)) More",
                            systemImage: "chevron.down"
                        )
                    }
                }
            }
        }
    }

    private var hasActiveMediaFilters: Bool {
        [
            model.mediaAccountFilter,
            model.mediaChatIDFilter,
            model.mediaMessageIDFilter,
            model.mediaFilenameQuery,
            model.mediaTypeFilter,
            model.mediaFileExtensionFilter
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func commitFilenameQuery(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != model.mediaFilenameQuery else { return }
        model.mediaFilenameQuery = normalized
        scheduleMediaReload()
    }

    private func commitMediaType(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized != model.mediaTypeFilter else { return }
        model.mediaTypeFilter = normalized
        scheduleMediaReload()
    }

    private func commitFileExtension(_ value: String) {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "." })
            .lowercased()
        guard normalized != model.mediaFileExtensionFilter else { return }
        model.mediaFileExtensionFilter = normalized
        scheduleMediaReload()
    }

    private func scheduleMediaReload() {
        listState.resetVisibleLimit()
        selection = nil
        mediaReloadTask?.cancel()
        mediaReloadTask = Task {
            await model.loadMediaFiles()
        }
    }

    private func resetLocalPresentation() {
        textFilterResetRevision &+= 1
        listState = MediaFileListState()
        selection = nil
    }
}

private struct DebouncedMediaTextField: View {
    var prompt: String
    @Binding var text: String
    @Binding var resetRevision: UInt
    @State private var draft: String
    @State private var debounceGate = MediaFilenameDebounceGate()

    init(prompt: String, text: Binding<String>, resetRevision: Binding<UInt>) {
        self.prompt = prompt
        _text = text
        _resetRevision = resetRevision
        _draft = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        let taskID = DebouncedMediaTextTaskID(
            draft: draft,
            resetRevision: resetRevision
        )

        TextField(prompt, text: $draft)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                debounceGate.cancelPending()
                text = draft
            }
            .task(id: taskID) {
                let ticket = debounceGate.schedule(query: taskID.draft)
                if !ticket.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled,
                      resetRevision == taskID.resetRevision,
                      debounceGate.accepts(ticket) else { return }
                if text != ticket.query {
                    text = ticket.query
                }
            }
            .onChange(of: text) {
                debounceGate.cancelPending()
                if draft != text {
                    draft = text
                }
            }
            .onChange(of: resetRevision) {
                debounceGate.cancelPending()
                draft = text
            }
    }
}

private struct DebouncedMediaTextTaskID: Equatable {
    var draft: String
    var resetRevision: UInt
}

private struct MediaCoreFilterControls: View {
    @Bindable var model: AppModel
    var reload: () -> Void
    var clear: () -> Void

    var body: some View {
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
            Button(action: reload) {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            Button(action: clear) {
                Label("Clear", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}

private struct MediaTableRow: Identifiable {
    var id: CoreMediaFile.ID
    var filename: String
    var typeTitle: String
    var fileExtension: String?
    var downloadedText: String
    var accountID: String
    var chatTitle: String
    var chatMetadata: String
    var sizeText: String

    init(file: CoreMediaFile) {
        self.id = file.id
        self.filename = file.suggestedFilename
        self.typeTitle = file.displayType.title
        self.fileExtension = file.fileExtension
        self.downloadedText = DisplayFormat.shortDateTime(file.downloadedAt)
        self.accountID = file.accountID
        self.chatTitle = file.displayTitle
        self.chatMetadata = "\(file.chatID) / \(file.messageID)"
        self.sizeText = file.fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? ""
    }
}

private struct MediaManagementTable: View {
    var rows: [MediaTableRow]
    @Binding var selection: CoreMediaFile.ID?

    var body: some View {
        Table(rows, selection: $selection) {
            TableColumn("Filename") { row in
                Text(row.filename)
                    .lineLimit(1)
            }
            .width(min: 170, ideal: 240)

            TableColumn("Type") { row in
                Text(row.typeTitle)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Extension") { row in
                Text(row.fileExtension.map { ".\($0)" } ?? "—")
                    .foregroundStyle(row.fileExtension == nil ? .secondary : .primary)
            }
            .width(min: 75, ideal: 90)

            TableColumn("Downloaded") { row in
                Text(row.downloadedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Account") { row in
                Text(row.accountID)
            }
                .width(min: 90, ideal: 120)

            TableColumn("Chat") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.chatTitle)
                        .lineLimit(1)
                    Text(row.chatMetadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("Size") { row in
                Text(row.sizeText)
            }
            .width(min: 80, ideal: 110)
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
                    GridRow { Text("Type").foregroundStyle(.secondary); Text(file.displayType.title) }
                    GridRow { Text("Extension").foregroundStyle(.secondary); Text(file.fileExtension.map { ".\($0)" } ?? "—") }
                    GridRow { Text("Content Type").foregroundStyle(.secondary); Text(file.contentType ?? file.mimeType ?? "—") }
                    GridRow { Text("Size").foregroundStyle(.secondary); Text(file.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "") }
                    if let location = file.filePath ?? file.bestURLString, !location.isEmpty {
                        GridRow {
                            Text("Location").foregroundStyle(.secondary)
                            Text(location)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .help(location)
                        }
                    }
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
                    Text("Preview \(file.displayType.title.lowercased())")
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
        return file.fileExtension.map(supportedExtensions.contains) ?? false
    }
}
