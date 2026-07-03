import SwiftUI

struct OriginsView: View {
    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                filters
                originsTable
            }
            .padding(20)

            OriginInspectorView(model: model)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        }
        .navigationTitle("Origins")
        .task {
            if model.origins.isEmpty {
                await model.loadOrigins()
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search title, username, id", text: $model.originSearch)
                    .textFieldStyle(.roundedBorder)
                TextField("Account", text: $model.originAccountFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Picker("Type", selection: $model.originTypeFilter) {
                    Text("Any type").tag("")
                    Text("Group").tag("group")
                    Text("Channel").tag("channel")
                    Text("Topic").tag("topic")
                    Text("Private").tag("private")
                    Text("Configured").tag("configured_chat")
                    Text("Unknown").tag("unknown")
                }
                .frame(width: 150)
                Toggle("Archived", isOn: $model.includeArchivedOrigins)
                Button {
                    Task { await model.loadOrigins() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
            HStack {
                TextField("Tag filter", text: $model.originTagFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button {
                    let account = model.originAccountFilter.isEmpty ? model.selectedProfile?.name ?? "" : model.originAccountFilter
                    Task { await model.discoverOrigins(accountID: account) }
                } label: {
                    Label("Discover", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(model.originAccountFilter.isEmpty)
                Spacer()
                Text("\(model.filteredOrigins.count) visible / \(model.origins.count) loaded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var originsTable: some View {
        Table(model.filteredOrigins, selection: $model.selectedOriginID) {
            TableColumn("Title") { origin in
                HStack(spacing: 8) {
                    if origin.isTopic {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(origin.displayTitle)
                            .lineLimit(1)
                        Text("\(origin.originID) / topic \(origin.topicID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("Account") { origin in
                Text(origin.accountID)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Type") { origin in
                StatusBadge(text: origin.originType)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Backup") { origin in
                let enabled = origin.backupPolicy?.enabled ?? false
                StatusBadge(text: enabled ? "On" : "Off", kind: enabled ? .success : .neutral)
            }
            .width(min: 80, ideal: 90)

            TableColumn("Tags") { origin in
                Text(origin.backupPolicy?.tags ?? "")
                    .lineLimit(1)
            }

            TableColumn("Last Message") { origin in
                Text(DisplayFormat.shortDateTime(origin.lastMessageAt))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180)
        }
    }
}

private struct OriginInspectorView: View {
    @Bindable var model: AppModel
    @State private var enabled = false
    @State private var captureText = true
    @State private var captureMediaMetadata = true
    @State private var downloadMedia = false
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let origin = model.selectedOrigin {
                Text(origin.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow { Text("Account").foregroundStyle(.secondary); Text(origin.accountID) }
                    GridRow { Text("Origin").foregroundStyle(.secondary); Text("\(origin.originID)") }
                    GridRow { Text("Topic").foregroundStyle(.secondary); Text("\(origin.topicID)") }
                    GridRow { Text("Type").foregroundStyle(.secondary); Text(origin.originType) }
                    GridRow { Text("Archived").foregroundStyle(.secondary); Text(origin.isArchived ? "Yes" : "No") }
                }
                .font(.callout)

                Divider()

                Toggle("Enabled", isOn: $enabled)
                Toggle("Capture text", isOn: $captureText)
                Toggle("Capture media metadata", isOn: $captureMediaMetadata)
                Toggle("Download media", isOn: $downloadMedia)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TagEditor(tags: $tags)
                }

                HStack {
                    Button {
                        Task {
                            await model.savePolicy(
                                for: origin,
                                policy: CoreBackupPolicy(
                                    source: origin.source,
                                    accountID: origin.accountID,
                                    originID: origin.originID,
                                    topicID: origin.topicID,
                                    enabled: enabled,
                                    captureText: captureText,
                                    captureMediaMetadata: captureMediaMetadata,
                                    downloadMedia: downloadMedia,
                                    tags: tags.nilIfEmpty
                                )
                            )
                        }
                    } label: {
                        Label("Save Policy", systemImage: "checkmark")
                    }
                    Button {
                        Task { await model.archiveSelectedOrigin(!origin.isArchived) }
                    } label: {
                        Label(origin.isArchived ? "Restore" : "Archive", systemImage: origin.isArchived ? "arrow.uturn.backward" : "archivebox")
                    }
                }

                Button(role: .destructive) {
                    Task { await model.deleteSelectedOrigin() }
                } label: {
                    Label("Delete Origin Metadata", systemImage: "trash")
                }
            } else {
                EmptyStateView(title: "Select an origin", detail: "Pick a row to edit backup policy and archive state.", systemImage: "rectangle.stack")
            }
            Spacer()
        }
        .padding(20)
        .background(.regularMaterial)
        .onChange(of: model.selectedOriginID) {
            syncPolicy()
        }
        .onAppear(perform: syncPolicy)
    }

    private func syncPolicy() {
        guard let origin = model.selectedOrigin else { return }
        let policy = origin.backupPolicy ?? CoreBackupPolicy()
        enabled = policy.enabled
        captureText = policy.captureText
        captureMediaMetadata = policy.captureMediaMetadata
        downloadMedia = policy.downloadMedia
        tags = policy.tags ?? ""
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
