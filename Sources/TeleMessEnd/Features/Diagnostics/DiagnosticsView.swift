import SwiftUI

private struct DiagnosticsLoadKey: Hashable {
    var sessionRevision: UInt64
    var section: DiagnosticsSection
}

struct DiagnosticsView: View {
    @Bindable var model: AppModel
    @State private var selectedOperationEventID: CoreOperationEvent.ID?
    @State private var selectedParticipantID: CoreParticipant.ID?
    @State private var selectedCursorID: CoreCaptureCursor.ID?
    @State private var selectedMediaFileID: CoreMediaFile.ID?
    @State private var pendingDeleteOperationEvent: CoreOperationEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("View", selection: $model.diagnosticsSelection) {
                    ForEach(DiagnosticsSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Spacer()
            }

            HStack {
                TextField("Account filter", text: $model.diagnosticsAccountFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: UILayout.standardField)
                TextField("Origin ID", text: $model.diagnosticsOriginIDFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: UILayout.compactField)
                TextField("Status", text: $model.diagnosticsStatusFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: UILayout.compactField)
                Button {
                    if let originID = Int(model.diagnosticsOriginIDFilter), !model.diagnosticsAccountFilter.isEmpty {
                        Task { await model.refreshParticipants(accountID: model.diagnosticsAccountFilter, originID: originID) }
                    }
                } label: {
                    Label("Refresh Participants", systemImage: "person.2.badge.gearshape")
                }
                .disabled(model.isLoading || model.diagnosticsAccountFilter.isEmpty || Int(model.diagnosticsOriginIDFilter) == nil)
            }

            content
        }
        .padding(20)
        .navigationTitle("Diagnostics")
        .task(id: DiagnosticsLoadKey(sessionRevision: model.sessionRevision, section: model.diagnosticsSelection)) {
            clearDetailSelection()
            pendingDeleteOperationEvent = nil
        }
        .alert("Delete operation event?", isPresented: Binding(
            get: { pendingDeleteOperationEvent != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteOperationEvent = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                if let event = pendingDeleteOperationEvent {
                    Task {
                        if await model.deleteOperationEvent(event) {
                            selectedOperationEventID = nil
                        }
                    }
                }
                pendingDeleteOperationEvent = nil
            }
            .disabled(model.isLoading)
            Button("Cancel", role: .cancel) {
                pendingDeleteOperationEvent = nil
            }
        } message: {
            Text("This removes the selected operation event row from the core diagnostics list.")
        }
    }

    @ViewBuilder
    private var content: some View {
        AdaptiveDetailLayout(hasDetail: selectedDetailPayload != nil) {
            tableContent
        } detail: {
            DetailPanel {
                RawPayloadView(title: selectedDetailTitle, payload: selectedDetailPayload)
            }
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        switch model.diagnosticsSelection {
        case .operationEvents:
            if model.operationEvents.isEmpty {
                EmptyStateView(title: "No operation events", detail: "Failed, partial, and rate-limited core operations appear here.", systemImage: "exclamationmark.triangle")
            } else {
                OperationEventsTable(events: model.operationEvents, selection: $selectedOperationEventID, isLoading: model.isLoading) { event in
                    pendingDeleteOperationEvent = event
                }
            }
        case .participants:
            if model.participants.isEmpty {
                EmptyStateView(title: "No participants", detail: "Filter by account/origin or refresh participants from Telegram.", systemImage: "person.2")
            } else {
                ParticipantsTable(participants: model.participants, selection: $selectedParticipantID)
            }
        case .cursors:
            if model.cursors.isEmpty {
                EmptyStateView(title: "No capture cursors", detail: "Backfill and catch-up cursor rows appear here.", systemImage: "point.3.connected.trianglepath.dotted")
            } else {
                CaptureCursorsTable(cursors: model.cursors, selection: $selectedCursorID)
            }
        case .media:
            if model.mediaFiles.isEmpty {
                EmptyStateView(title: "No media files", detail: "Downloaded media metadata appears here when policies enable media download.", systemImage: "paperclip")
            } else {
                MediaFilesTable(files: model.mediaFiles, selection: $selectedMediaFileID)
            }
        }
    }

    private var selectedDetailTitle: String {
        switch model.diagnosticsSelection {
        case .operationEvents:
            if let event = selectedOperationEvent {
                return "Operation Event #\(event.id)"
            }
            return "Operation Event Payload"
        case .participants:
            if let participant = selectedParticipant {
                return participant.displayName ?? participant.username ?? "Participant \(participant.userID)"
            }
            return "Participant Payload"
        case .cursors:
            if let cursor = selectedCursor {
                return "Cursor \(cursor.originID) / topic \(cursor.topicID)"
            }
            return "Cursor Payload"
        case .media:
            if let file = selectedMediaFile {
                return "Media \(file.chatID) / \(file.messageID)"
            }
            return "Media Payload"
        }
    }

    private var selectedDetailPayload: JSONValue? {
        switch model.diagnosticsSelection {
        case .operationEvents:
            selectedOperationEvent?.rawJSON
        case .participants:
            selectedParticipant?.rawJSON
        case .cursors:
            selectedCursor?.rawJSON
        case .media:
            selectedMediaFile?.rawJSON
        }
    }

    private var selectedOperationEvent: CoreOperationEvent? {
        guard let selectedOperationEventID else { return nil }
        return model.operationEvents.first { $0.id == selectedOperationEventID }
    }

    private var selectedParticipant: CoreParticipant? {
        guard let selectedParticipantID else { return nil }
        return model.participants.first { $0.id == selectedParticipantID }
    }

    private var selectedCursor: CoreCaptureCursor? {
        guard let selectedCursorID else { return nil }
        return model.cursors.first { $0.id == selectedCursorID }
    }

    private var selectedMediaFile: CoreMediaFile? {
        guard let selectedMediaFileID else { return nil }
        return model.mediaFiles.first { $0.id == selectedMediaFileID }
    }

    private func clearDetailSelection() {
        selectedOperationEventID = nil
        selectedParticipantID = nil
        selectedCursorID = nil
        selectedMediaFileID = nil
    }
}

private struct ParticipantsTable: View {
    var participants: [CoreParticipant]
    @Binding var selection: CoreParticipant.ID?

    var body: some View {
        Table(participants, selection: $selection) {
            TableColumn("Account") { Text($0.accountID) }
            TableColumn("Origin") { Text("\($0.originID)") }
            TableColumn("User") { participant in
                VStack(alignment: .leading, spacing: 2) {
                    Text(participant.displayName ?? participant.username ?? "\(participant.userID)")
                    Text("\(participant.userID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Role") { Text($0.role ?? "") }
            TableColumn("Updated") { TimestampText($0.updatedAt) }
        }
    }
}

private struct CaptureCursorsTable: View {
    var cursors: [CoreCaptureCursor]
    @Binding var selection: CoreCaptureCursor.ID?

    var body: some View {
        Table(cursors, selection: $selection) {
            TableColumn("Account") { Text($0.accountID) }
            TableColumn("Origin") { cursor in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cursor.originTitle ?? "\(cursor.originID)")
                    Text("topic \(cursor.topicID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Last Message") { Text($0.lastMessageID.map(String.init) ?? "") }
            TableColumn("Message Time") { TimestampText($0.lastMessageAt) }
            TableColumn("Backfill") { TimestampText($0.lastBackfillAt) }
        }
    }
}

private struct MediaFilesTable: View {
    var files: [CoreMediaFile]
    @Binding var selection: CoreMediaFile.ID?

    var body: some View {
        Table(files, selection: $selection) {
            TableColumn("Downloaded") { TimestampText($0.downloadedAt) }
            TableColumn("Account") { Text($0.accountID) }
            TableColumn("Chat") { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.chatTitle ?? "\(file.chatID)")
                    Text("\(file.chatID) / \(file.messageID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Kind") { Text($0.mediaKind ?? "") }
            TableColumn("Size") { Text($0.fileSize.map(String.init) ?? "") }
            TableColumn("Preview") { Text($0.previewKind ?? $0.contentType ?? "") }
            TableColumn("Path") { Text($0.filePath ?? $0.bestURLString ?? "").lineLimit(1) }
        }
    }
}
