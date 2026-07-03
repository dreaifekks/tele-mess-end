import SwiftUI

struct DiagnosticsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("View", selection: $model.diagnosticsSelection) {
                    ForEach(DiagnosticsSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Spacer()

                Button {
                    Task { await model.loadDiagnostics() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }

            HStack {
                TextField("Account filter", text: $model.diagnosticsAccountFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Origin ID", text: $model.diagnosticsOriginIDFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                TextField("Status", text: $model.diagnosticsStatusFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                Button {
                    if let originID = Int(model.diagnosticsOriginIDFilter), !model.diagnosticsAccountFilter.isEmpty {
                        Task { await model.refreshParticipants(accountID: model.diagnosticsAccountFilter, originID: originID) }
                    }
                } label: {
                    Label("Refresh Participants", systemImage: "person.2.badge.gearshape")
                }
                .disabled(model.diagnosticsAccountFilter.isEmpty || Int(model.diagnosticsOriginIDFilter) == nil)
            }

            content
        }
        .padding(20)
        .navigationTitle("Diagnostics")
        .task {
            await model.loadDiagnostics()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.diagnosticsSelection {
        case .operationEvents:
            if model.operationEvents.isEmpty {
                EmptyStateView(title: "No operation events", detail: "Failed, partial, and rate-limited core operations appear here.", systemImage: "exclamationmark.triangle")
            } else {
                OperationEventsTable(events: model.operationEvents)
            }
        case .participants:
            if model.participants.isEmpty {
                EmptyStateView(title: "No participants", detail: "Filter by account/origin or refresh participants from Telegram.", systemImage: "person.2")
            } else {
                ParticipantsTable(participants: model.participants)
            }
        case .cursors:
            if model.cursors.isEmpty {
                EmptyStateView(title: "No capture cursors", detail: "Backfill and catch-up cursor rows appear here.", systemImage: "point.3.connected.trianglepath.dotted")
            } else {
                CaptureCursorsTable(cursors: model.cursors)
            }
        case .media:
            if model.mediaFiles.isEmpty {
                EmptyStateView(title: "No media files", detail: "Downloaded media metadata appears here when policies enable media download.", systemImage: "paperclip")
            } else {
                MediaFilesTable(files: model.mediaFiles)
            }
        }
    }
}

private struct ParticipantsTable: View {
    var participants: [CoreParticipant]

    var body: some View {
        Table(participants) {
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
            TableColumn("Updated") { Text(DisplayFormat.shortDateTime($0.updatedAt)).foregroundStyle(.secondary) }
        }
    }
}

private struct CaptureCursorsTable: View {
    var cursors: [CoreCaptureCursor]

    var body: some View {
        Table(cursors) {
            TableColumn("Account") { Text($0.accountID) }
            TableColumn("Origin") { cursor in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cursor.originTitle ?? "\(cursor.originID)")
                    Text("topic \(cursor.topicID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Last Message") { Text("\($0.lastMessageID)") }
            TableColumn("Message Time") { Text(DisplayFormat.shortDateTime($0.lastMessageAt)).foregroundStyle(.secondary) }
            TableColumn("Backfill") { Text(DisplayFormat.shortDateTime($0.lastBackfillAt)).foregroundStyle(.secondary) }
        }
    }
}

private struct MediaFilesTable: View {
    var files: [CoreMediaFile]

    var body: some View {
        Table(files) {
            TableColumn("Downloaded") { Text(DisplayFormat.shortDateTime($0.downloadedAt)).foregroundStyle(.secondary) }
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
            TableColumn("Path") { Text($0.filePath).lineLimit(1) }
        }
    }
}
