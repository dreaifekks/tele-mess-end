import SwiftUI

struct DailySummaryView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var selectedRecordIDs: Set<DailySummaryRecord.ID> = []
    @State private var pendingDeleteRecords: [DailySummaryRecord] = []
    @State private var showingDeleteConfirmation = false
    @State private var isDetailExpanded = false
    @State private var sortOrder = [
        KeyPathComparator(\DailySummaryRecord.updatedSortValue, order: .reverse)
    ]
    @FocusState private var focusedArea: SummaryFocusArea?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryHeader

            if !model.dailySummaryRecords.isEmpty {
                summaryRecordsContent
            } else {
                EmptyStateView(title: emptyTitle, detail: emptyDetail, systemImage: "star")
            }

            if !isDetailExpanded {
                recentRuns
            }
        }
        .padding(20)
        .navigationTitle("Daily Summary")
        .disabled(model.isLoading)
        .task(id: model.sessionRevision) {
            resetForSession()
        }
        .task {
            await model.runDailySummaryProgressLoop()
        }
        .onChange(of: model.dailySummaryRecords.map(\.id)) {
            let ids = Set(model.dailySummaryRecords.map(\.id))
            selectedRecordIDs = selectedRecordIDs.intersection(ids)
            if selectedRecordIDs.isEmpty {
                isDetailExpanded = false
            }
        }
        .onChange(of: model.includeDeletedDailySummaryRecords) {
            Task { await model.loadDailySummaries() }
        }
        .onChange(of: selectedRecordIDs) {
            if let selectedRecord, selectedRecord.contentMD == nil {
                Task { await model.loadDailySummaryRecordContent(selectedRecord) }
            }
            if selectedRecordIDs.isEmpty {
                isDetailExpanded = false
            }
        }
        .confirmationDialog(
            "Delete \(pendingDeleteRecords.count) summary record\(pendingDeleteRecords.count == 1 ? "" : "s")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePendingRecords()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRecords = []
            }
        } message: {
            Text("Deleted records are soft-deleted in core and can be restored when Show Deleted is enabled.")
        }
    }

    private func resetForSession() {
        selectedRecordIDs.removeAll()
        pendingDeleteRecords.removeAll()
        showingDeleteConfirmation = false
        isDetailExpanded = false
        sortOrder = [KeyPathComparator(\DailySummaryRecord.updatedSortValue, order: .reverse)]
        focusedArea = nil
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                StatusBadge(
                    text: model.summarySettingsStore.settings.enabled ? "Scheduled" : "Manual",
                    kind: model.summarySettingsStore.settings.enabled ? .success : .neutral
                )
                Text(model.summarySettingsStore.settings.scheduleText)
                    .font(.title3.monospacedDigit())
                if let job = model.latestDailySummaryJob {
                    StatusBadge(text: "Job \(job.status)", kind: statusKind(job.status))
                }
                Spacer()
                Button {
                    Task { await model.runDailyPackageAndSummary() }
                } label: {
                    Label("Run Analysis", systemImage: "play.circle")
                }
                .disabled(model.activeDailySummaryJob != nil)
                if let activeJob = model.activeDailySummaryJob {
                    Button {
                        Task { await model.cancelDailySummaryJob(activeJob) }
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }
                Button {
                    Task { await model.refreshDailySummaryProgress() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Toggle("Show Deleted", isOn: $model.includeDeletedDailySummaryRecords)
                    .toggleStyle(.checkbox)
                Button {
                    model.settingsSection = .summary
                    openSettings()
                } label: {
                    Label("Summary Settings", systemImage: "gearshape")
                }
            }

            HStack(alignment: .center, spacing: 10) {
                if let job = model.latestDailySummaryJob {
                    SummaryProgressMeter(
                        title: "Analysis",
                        status: job.status,
                        label: job.progressLabel,
                        current: job.progressCurrent,
                        total: job.progressTotal,
                        detail: jobDetail(job)
                    )
                }
                Spacer()
                if !selectedRecords.isEmpty {
                    Text("\(selectedRecords.count) selected")
                        .foregroundStyle(.secondary)
                    if !selectedDeletedRecords.isEmpty {
                        Button {
                            restoreSelectedRecords()
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                    }
                    if !selectedActiveRecords.isEmpty {
                        Button(role: .destructive) {
                            requestDeleteSelectedRecords()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var selectedRecord: DailySummaryRecord? {
        summaryRecordRows.first { selectedRecordIDs.contains($0.id) }
    }

    private var selectedRecords: [DailySummaryRecord] {
        summaryRecordRows.filter { selectedRecordIDs.contains($0.id) }
    }

    private var selectedActiveRecords: [DailySummaryRecord] {
        selectedRecords.filter { $0.deleted != true }
    }

    private var selectedDeletedRecords: [DailySummaryRecord] {
        selectedRecords.filter { $0.deleted == true }
    }

    private var summaryRecordsContent: some View {
        Group {
            if isDetailExpanded {
                SummaryRecordDetailPanel(
                    model: model,
                    record: selectedRecord,
                    selectedCount: selectedRecords.count,
                    isExpanded: isDetailExpanded,
                    onToggleExpanded: { isDetailExpanded.toggle() },
                    onDelete: requestDeleteSelectedRecords,
                    onRestore: restoreSelectedRecords
                )
            } else {
                HSplitView {
                    summaryRecordsTable
                        .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

                    SummaryRecordDetailPanel(
                        model: model,
                        record: selectedRecord,
                        selectedCount: selectedRecords.count,
                        isExpanded: isDetailExpanded,
                        onToggleExpanded: { isDetailExpanded.toggle() },
                        onDelete: requestDeleteSelectedRecords,
                        onRestore: restoreSelectedRecords
                    )
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(minHeight: 360)
        .focusable()
        .focused($focusedArea, equals: .records)
        .onMoveCommand { direction in
            moveSelection(direction)
        }
    }

    private var summaryRecordsTable: some View {
        Table(summaryRecordRows, selection: $selectedRecordIDs, sortOrder: $sortOrder) {
            summaryRecordColumns
        }
    }

    @TableColumnBuilder<DailySummaryRecord, KeyPathComparator<DailySummaryRecord>>
    private var summaryRecordColumns: some TableColumnContent<DailySummaryRecord, KeyPathComparator<DailySummaryRecord>> {
        TableColumn("Title", sortUsing: KeyPathComparator(\DailySummaryRecord.titleSortValue)) { record in
            recordCell(record) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if record.important == true {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        Text(record.title ?? record.summaryID)
                            .lineLimit(1)
                        if record.deleted == true {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(.red)
                                .help("Deleted")
                        }
                    }
                    Text(record.contentPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }

        TableColumn("Type", sortUsing: KeyPathComparator(\DailySummaryRecord.recordTypeSortValue)) { record in
            recordCell(record) {
                Label(record.recordTypeDisplayName, systemImage: summaryRecordTypeSystemImage(record.recordType))
                    .lineLimit(1)
            }
        }

        TableColumn("Date", sortUsing: KeyPathComparator(\DailySummaryRecord.dateSortValue)) { record in
            recordCell(record) { Text(record.date ?? "") }
        }

        TableColumn("Tags", sortUsing: KeyPathComparator(\DailySummaryRecord.tagsSortValue)) { record in
            recordCell(record) { Text(tagsText(record.tags)).lineLimit(1) }
        }

        TableColumn("Provider", sortUsing: KeyPathComparator(\DailySummaryRecord.providerSortValue)) { record in
            recordCell(record) { Text(record.provider ?? "") }
        }

        TableColumn("Updated", sortUsing: KeyPathComparator(\DailySummaryRecord.updatedSortValue)) { record in
            recordCell(record) {
                Text(DisplayFormat.shortDateTime(record.updatedAt ?? record.createdAt))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recentRuns: some View {
        HStack(alignment: .top, spacing: 18) {
            recentRunColumn(title: "Analysis Jobs", values: model.dailySummaryJobs.map { job in
                "\((job.date ?? "-"))  \(job.status)  \(progressText(current: job.progressCurrent, total: job.progressTotal, label: job.progressLabel))"
            })
            recentRunColumn(title: "Package Runs", values: model.dailyPackageRuns.map { run in
                "\(run.date)  \(run.status)  \(progressText(current: run.progressCurrent, total: run.progressTotal, label: run.progressLabel))"
            })
            recentRunColumn(title: "Summary Runs", values: model.dailySummaryRuns.map { run in
                "\((run.date ?? "-"))  \(run.status)  \(progressText(current: run.progressCurrent, total: run.progressTotal, label: run.progressLabel))"
            })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentRunColumn(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            if values.isEmpty {
                Text("No runs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values.prefix(3), id: \.self) { value in
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyTitle: String {
        "No summary records"
    }

    private var emptyDetail: String {
        model.includeDeletedDailySummaryRecords ? "No active or deleted records match the current scope." : "Run analysis or reload records from core."
    }

    private var summaryRecordRows: [DailySummaryRecord] {
        sortedRecords(model.dailySummaryRecords)
    }

    private func recordCell<Content: View>(_ record: DailySummaryRecord, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func sortedRecords(_ records: [DailySummaryRecord]) -> [DailySummaryRecord] {
        records.sorted { lhs, rhs in
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
            return lhs.summaryID.localizedCaseInsensitiveCompare(rhs.summaryID) == .orderedAscending
        }
    }

    private func tagsText(_ tags: [String]?) -> String {
        guard let tags, !tags.isEmpty else { return "-" }
        return tags.joined(separator: ", ")
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let rows = summaryRecordRows
        guard !rows.isEmpty else { return }
        let currentIndex = selectedRecord.flatMap { record in
            rows.firstIndex { $0.id == record.id }
        }
        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max((currentIndex ?? 0) - 1, 0)
        case .down:
            nextIndex = min((currentIndex ?? -1) + 1, rows.count - 1)
        default:
            return
        }
        selectedRecordIDs = [rows[nextIndex].id]
        focusedArea = .records
        if let selectedRecord, selectedRecord.contentMD == nil {
            Task { await model.loadDailySummaryRecordContent(selectedRecord) }
        }
    }

    private func requestDeleteSelectedRecords() {
        let records = selectedActiveRecords
        guard !records.isEmpty else { return }
        pendingDeleteRecords = records
        showingDeleteConfirmation = true
    }

    private func deletePendingRecords() {
        let records = pendingDeleteRecords
        let ids = Set(records.map(\.id))
        pendingDeleteRecords = []
        Task {
            if await model.deleteDailySummaryRecords(records) {
                selectedRecordIDs.subtract(ids)
                if selectedRecordIDs.isEmpty {
                    isDetailExpanded = false
                }
                focusedArea = .records
            }
        }
    }

    private func restoreSelectedRecords() {
        let records = selectedDeletedRecords
        let ids = Set(records.map(\.id))
        guard !records.isEmpty else { return }
        Task {
            if await model.restoreDailySummaryRecords(records) {
                selectedRecordIDs.subtract(ids)
                if selectedRecordIDs.isEmpty {
                    isDetailExpanded = false
                }
                focusedArea = .records
            }
        }
    }

    private func statusKind(_ status: String) -> StatusBadgeKind {
        switch status.lowercased() {
        case "completed":
            .success
        case "failed":
            .error
        case "cancel_requested", "cancelled", "canceled":
            .warning
        default:
            .neutral
        }
    }

    private func jobDetail(_ job: DailySummaryJob) -> String {
        if let error = job.error, !error.isEmpty {
            return error
        }
        return [
            job.packageRunID.map { "package \($0)" },
            job.summaryRunID.map { "summary \($0)" }
        ].compactMap { $0 }.joined(separator: "  ")
    }

    private func progressText(current: Int?, total: Int?, label: String?) -> String {
        var parts: [String] = []
        if let label, !label.isEmpty {
            parts.append(label)
        }
        if let total, total > 0 {
            parts.append("\(current ?? 0)/\(total)")
        }
        return parts.joined(separator: "  ")
    }
}

private struct SummaryProgressMeter: View {
    var title: String
    var status: String
    var label: String?
    var current: Int?
    var total: Int?
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                StatusBadge(text: status, kind: statusKind)
                if let label, !label.isEmpty {
                    Text(label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let total, total > 0 {
                    Text("\(current ?? 0)/\(total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let total, total > 0 {
                ProgressView(value: Double(current ?? 0), total: Double(total))
                    .controlSize(.small)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 160, alignment: .leading)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusKind: StatusBadgeKind {
        switch status.lowercased() {
        case "completed":
            .success
        case "failed":
            .error
        case "cancel_requested", "cancelled", "canceled":
            .warning
        default:
            .neutral
        }
    }
}

private enum SummaryFocusArea: Hashable {
    case records
}

private struct SummaryRecordDetailPanel: View {
    @Bindable var model: AppModel
    var record: DailySummaryRecord?
    var selectedCount = 0
    var isExpanded = false
    var onToggleExpanded: () -> Void = {}
    var onDelete: () -> Void = {}
    var onRestore: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let record {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(record.title ?? record.summaryID)
                                .font(.headline)
                                .lineLimit(2)
                            if record.deleted == true {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(.red)
                                    .help("Deleted")
                            }
                        }
                        Label(record.recordTypeDisplayName, systemImage: summaryRecordTypeSystemImage(record.recordType))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if selectedCount > 1 {
                            Text("\(selectedCount) records selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        onToggleExpanded()
                    } label: {
                        Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(record.contentPreview.isEmpty && record.contentMD == nil)
                }

                LazyVGrid(columns: detailColumns, alignment: .leading, spacing: 8) {
                    SummaryMetadataTile(title: "Type", value: record.recordTypeDisplayName)
                    SummaryMetadataTile(title: "Date", value: record.date ?? "-")
                    SummaryMetadataTile(title: "Provider", value: record.provider ?? "-")
                }

                if record.contentMD == nil {
                    Button {
                        Task { await model.loadDailySummaryRecordContent(record) }
                    } label: {
                        Label("Load Content", systemImage: "arrow.down.doc")
                    }
                }
                if record.deleted == true {
                    Button {
                        onRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(selectedCount > 1 ? "Delete Selected" : "Delete", systemImage: "trash")
                    }
                }

                ScrollView {
                    MarkdownContentView(markdown: record.contentMD ?? record.contentPreview)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                EmptyStateView(title: "Select summary", detail: "Pick one or more daily summary rows to inspect metadata and content.", systemImage: "doc.text.magnifyingglass")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var detailColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8, alignment: .leading),
            GridItem(.flexible(), spacing: 8, alignment: .leading)
        ]
    }
}

private func summaryRecordTypeSystemImage(_ recordType: String) -> String {
    switch recordType {
    case "important_daily":
        "star.fill"
    case "point_daily":
        "list.bullet.rectangle.portrait"
    default:
        "doc.text"
    }
}

private struct SummaryMetadataTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MarkdownContentView: View {
    var markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(headingFont(level))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 8 : 4)
                .padding(.bottom, 2)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.body)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        case .quote(let text):
            Text(inlineMarkdown(text))
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(inlineMarkdown(cell))
                    .font(isHeader ? Font.caption.weight(.semibold) : Font.caption)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(isHeader ? Color.secondary.opacity(0.12) : Color.clear)
                    .overlay {
                        Rectangle()
                            .stroke(Color.secondary.opacity(0.22), lineWidth: 0.5)
                    }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:
            .title2
        case 2:
            .title3
        case 3:
            .headline
        default:
            .subheadline
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let rendered = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return rendered
        }
        return AttributedString(text)
    }
}
