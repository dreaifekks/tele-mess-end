import Foundation
import SwiftUI

struct OriginsView: View {
    @Bindable var model: AppModel
    @State private var expandedGroups = Set<String>()
    @State private var manageMode = false
    @State private var managedSelection = Set<CoreOrigin.ID>()
    @State private var sortOrder: [KeyPathComparator<CoreOrigin>] = []

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                filters
                originsTable
            }
            .padding(20)

            OriginInspectorView(model: model, selectedOrigins: inspectorOrigins)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        }
        .navigationTitle("Origins")
        .task {
            if model.origins.isEmpty {
                await model.loadOrigins()
            }
        }
        .onChange(of: model.includeArchivedOrigins) {
            Task { await model.loadOrigins() }
        }
        .onChange(of: manageMode) {
            if manageMode {
                if let selected = model.selectedOriginID {
                    managedSelection = [selected]
                }
            } else {
                model.selectedOriginID = managedSelection.first ?? model.selectedOriginID
                managedSelection.removeAll()
            }
        }
        .onChange(of: managedSelection) {
            if manageMode, managedSelection.count == 1 {
                model.selectedOriginID = managedSelection.first
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
                Picker("Backup", selection: $model.originBackupFilter) {
                    ForEach(OriginBackupFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
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
                Toggle("Backup First", isOn: $model.originBackupFirst)
                Button {
                    sortOrder.removeAll()
                } label: {
                    Label("Default Sort", systemImage: "arrow.up.arrow.down")
                }
                Button {
                    let account = model.originAccountFilter.isEmpty ? model.selectedProfile?.name ?? "" : model.originAccountFilter
                    Task { await model.discoverOrigins(accountID: account) }
                } label: {
                    Label("Discover", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(model.originAccountFilter.isEmpty)
                Spacer()
                Toggle("Manage", isOn: $manageMode)
                    .toggleStyle(.button)
                Text("\(originRows.count) visible / \(model.origins.count) loaded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var originsTable: some View {
        if manageMode {
            Table(originRows, selection: $managedSelection, sortOrder: $sortOrder) {
                originColumns
            }
        } else {
            Table(originRows, selection: $model.selectedOriginID, sortOrder: $sortOrder) {
                originColumns
            }
        }
    }

    @TableColumnBuilder<CoreOrigin, KeyPathComparator<CoreOrigin>>
    private var originColumns: some TableColumnContent<CoreOrigin, KeyPathComparator<CoreOrigin>> {
        TableColumn("Title", sortUsing: KeyPathComparator(\CoreOrigin.displayTitle)) { origin in
            HStack(spacing: 8) {
                if hasTopicChildren(origin) {
                    Button {
                        toggleExpanded(origin)
                    } label: {
                        Image(systemName: isExpanded(origin) ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded(origin) ? "Collapse topics" : "Show topics")
                } else if origin.isTopic {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
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

        TableColumn("Account", sortUsing: KeyPathComparator(\CoreOrigin.accountID)) { origin in
            Text(origin.accountID)
        }
        .width(min: 90, ideal: 120)

        TableColumn("Type", sortUsing: KeyPathComparator(\CoreOrigin.originType)) { origin in
            StatusBadge(text: origin.originType)
        }
        .width(min: 90, ideal: 110)

        TableColumn("Backup", sortUsing: KeyPathComparator(\CoreOrigin.backupSortValue)) { origin in
            let enabled = origin.backupPolicy?.enabled ?? false
            StatusBadge(text: enabled ? "On" : "Off", kind: enabled ? .success : .neutral)
        }
        .width(min: 80, ideal: 90)

        TableColumn("Tags", sortUsing: KeyPathComparator(\CoreOrigin.tagsSortValue)) { origin in
            Text(origin.backupPolicy?.tags ?? "")
                .lineLimit(1)
        }

        TableColumn("Last Message", sortUsing: KeyPathComparator(\CoreOrigin.lastMessageSortValue)) { origin in
            Text(DisplayFormat.shortDateTime(origin.lastMessageAt))
                .foregroundStyle(.secondary)
        }
        .width(min: 140, ideal: 180)
    }

    private var sortedOrigins: [CoreOrigin] {
        let candidates = sortOrder.isEmpty ? model.filteredOrigins : model.matchingOrigins
        if sortOrder.isEmpty {
            return candidates
        }
        return candidates.sorted { lhs, rhs in
            if model.originBackupFirst {
                let left = lhs.backupPolicy?.enabled == true
                let right = rhs.backupPolicy?.enabled == true
                if left != right {
                    return left && !right
                }
            }
            for comparator in sortOrder {
                switch comparator.compare(lhs, rhs) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    continue
                }
            }
            return compareHierarchy(lhs, rhs)
        }
    }

    private var originRows: [CoreOrigin] {
        sortedOrigins.filter { origin in
            if !origin.isTopic {
                return true
            }
            return shouldShowTopicsForFilters || expandedGroups.contains(groupKey(for: origin))
        }
    }

    private var shouldShowTopicsForFilters: Bool {
        model.originTypeFilter == "topic" ||
        !model.originSearch.isEmpty ||
        !model.originTagFilter.isEmpty ||
        model.originBackupFilter != .any
    }

    private var inspectorOrigins: [CoreOrigin] {
        if manageMode {
            return managedSelection.compactMap { id in
                model.origins.first { $0.id == id }
            }
        }
        if let origin = model.selectedOrigin {
            return [origin]
        }
        return []
    }

    private func hasTopicChildren(_ origin: CoreOrigin) -> Bool {
        guard !origin.isTopic else { return false }
        return model.origins.contains {
            $0.source == origin.source &&
            $0.accountID == origin.accountID &&
            $0.originID == origin.originID &&
            $0.topicID != 0
        }
    }

    private func isExpanded(_ origin: CoreOrigin) -> Bool {
        expandedGroups.contains(groupKey(for: origin))
    }

    private func toggleExpanded(_ origin: CoreOrigin) {
        let key = groupKey(for: origin)
        if expandedGroups.contains(key) {
            expandedGroups.remove(key)
        } else {
            expandedGroups.insert(key)
        }
    }

    private func groupKey(for origin: CoreOrigin) -> String {
        "\(origin.source):\(origin.accountID):\(origin.originID)"
    }

    private func compareHierarchy(_ lhs: CoreOrigin, _ rhs: CoreOrigin) -> Bool {
        if lhs.accountID != rhs.accountID {
            return lhs.accountID.localizedCaseInsensitiveCompare(rhs.accountID) == .orderedAscending
        }
        if lhs.originID != rhs.originID {
            return lhs.originID < rhs.originID
        }
        if lhs.topicID != rhs.topicID {
            if lhs.topicID == 0 { return true }
            if rhs.topicID == 0 { return false }
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }
        return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }
}

private struct OriginInspectorView: View {
    @Bindable var model: AppModel
    var selectedOrigins: [CoreOrigin]
    @State private var enabled = false
    @State private var captureText = true
    @State private var captureMediaMetadata = true
    @State private var downloadMedia = false
    @State private var tags = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedOrigins.count > 1 {
                bulkControls
            } else if let origin = selectedOrigins.first {
                singleOriginControls(origin)
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
        .onChange(of: selectedOrigins) {
            syncPolicy()
        }
        .onAppear(perform: syncPolicy)
        .alert("Delete origin metadata?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteOrigins(selectedOrigins) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes selected origin metadata, policy, and cursor rows through the core API. Stored messages remain unless the core changes that contract.")
        }
    }

    private var bulkControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(selectedOrigins.count) origins selected")
                .font(.headline)
            Text("Parent group operations also apply to loaded topic rows under that group.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    Task { await model.archiveOrigins(selectedOrigins, archived: true) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                Button {
                    Task { await model.archiveOrigins(selectedOrigins, archived: false) }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Origin Metadata", systemImage: "trash")
            }
        }
    }

    private func singleOriginControls(_ origin: CoreOrigin) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    Task { await model.archiveOrigins([origin], archived: !origin.isArchived) }
                } label: {
                    Label(origin.isArchived ? "Restore" : "Archive", systemImage: origin.isArchived ? "arrow.uturn.backward" : "archivebox")
                }
            }

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Origin Metadata", systemImage: "trash")
            }
        }
    }

    private func syncPolicy() {
        guard selectedOrigins.count == 1, let origin = selectedOrigins.first else { return }
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
