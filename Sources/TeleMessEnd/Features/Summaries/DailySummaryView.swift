import SwiftUI

struct DailySummaryView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var selectedRecordIDs: Set<DailySummaryRecord.ID> = []
    @State private var pendingDeleteRecords: [DailySummaryRecord] = []
    @State private var showingDeleteConfirmation = false
    @State private var isDetailExpanded = false
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
        .task {
            if model.dailySummaryRecords.isEmpty {
                await model.loadDailySummaries()
            }
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

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                StatusBadge(
                    text: model.summarySettingsStore.settings.enabled ? "Scheduled" : "Manual",
                    kind: model.summarySettingsStore.settings.enabled ? .success : .neutral
                )
                Text(model.summarySettingsStore.settings.scheduleText)
                    .font(.title3.monospacedDigit())
                Text("\(model.summarySettingsStore.settings.lookbackHours)h window")
                    .foregroundStyle(.secondary)
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
        model.dailySummaryRecords.first { selectedRecordIDs.contains($0.id) }
    }

    private var selectedRecords: [DailySummaryRecord] {
        model.dailySummaryRecords.filter { selectedRecordIDs.contains($0.id) }
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
        Table(model.dailySummaryRecords, selection: $selectedRecordIDs) {
            TableColumn("Title") { record in
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
            TableColumn("Date") { record in recordCell(record) { Text(record.date ?? "") } }
            TableColumn("Tags") { record in recordCell(record) { Text(tagsText(record.tags)).lineLimit(1) } }
            TableColumn("Provider") { record in recordCell(record) { Text(record.provider ?? "") } }
            TableColumn("Updated") { record in
                recordCell(record) {
                    Text(DisplayFormat.shortDateTime(record.updatedAt ?? record.createdAt))
                        .foregroundStyle(.secondary)
                }
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

    private func recordCell<Content: View>(_ record: DailySummaryRecord, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func tagsText(_ tags: [String]?) -> String {
        guard let tags, !tags.isEmpty else { return "-" }
        return tags.joined(separator: ", ")
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !model.dailySummaryRecords.isEmpty else { return }
        let currentIndex = selectedRecord.flatMap { record in
            model.dailySummaryRecords.firstIndex { $0.id == record.id }
        }
        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max((currentIndex ?? 0) - 1, 0)
        case .down:
            nextIndex = min((currentIndex ?? -1) + 1, model.dailySummaryRecords.count - 1)
        default:
            return
        }
        selectedRecordIDs = [model.dailySummaryRecords[nextIndex].id]
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
            await model.deleteDailySummaryRecords(records)
            selectedRecordIDs.subtract(ids)
            if selectedRecordIDs.isEmpty {
                isDetailExpanded = false
            }
            focusedArea = .records
        }
    }

    private func restoreSelectedRecords() {
        let records = selectedDeletedRecords
        let ids = Set(records.map(\.id))
        guard !records.isEmpty else { return }
        Task {
            await model.restoreDailySummaryRecords(records)
            selectedRecordIDs.subtract(ids)
            if selectedRecordIDs.isEmpty {
                isDetailExpanded = false
            }
            focusedArea = .records
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

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(number: Int, text: String)
    case table(headers: [String], rows: [[String]])
    case quote(String)
    case code(String)
    case divider
}

private enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var inCodeFence = false

        func flushParagraph() {
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        let lines = markdown.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeFence {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCodeFence = false
                } else {
                    flushParagraph()
                    inCodeFence = true
                }
                index += 1
                continue
            }

            if inCodeFence {
                codeLines.append(rawLine)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if let table = table(startingAt: index, in: lines) {
                flushParagraph()
                blocks.append(.table(headers: table.headers, rows: table.rows))
                index = table.nextIndex
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if let bullet = bullet(from: trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                index += 1
                continue
            }

            if let item = numbered(from: trimmed) {
                flushParagraph()
                blocks.append(.numbered(number: item.number, text: item.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        if inCodeFence {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func table(startingAt index: Int, in lines: [String]) -> (headers: [String], rows: [[String]], nextIndex: Int)? {
        guard index + 1 < lines.count,
              let headers = tableCells(from: lines[index]),
              headers.count > 1,
              let separator = tableCells(from: lines[index + 1]),
              separator.count == headers.count,
              isTableSeparator(separator) else {
            return nil
        }

        var rows: [[String]] = []
        var current = index + 2
        while current < lines.count {
            guard let cells = tableCells(from: lines[current]), !isTableSeparator(cells) else {
                break
            }
            rows.append(normalizedTableCells(cells, count: headers.count))
            current += 1
        }

        return (headers: headers, rows: rows, nextIndex: current)
    }

    private static func tableCells(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var content = trimmed
        if content.hasPrefix("|") {
            content.removeFirst()
        }
        if content.hasSuffix("|") {
            content.removeLast()
        }
        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard cells.count > 1, cells.contains(where: { !$0.isEmpty }) else {
            return nil
        }
        return cells
    }

    private static func isTableSeparator(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: " ", with: "")
            return compact.contains("-") && compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func normalizedTableCells(_ cells: [String], count: Int) -> [String] {
        if cells.count == count {
            return cells
        }
        if cells.count > count {
            return Array(cells.prefix(count))
        }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else {
            return nil
        }
        let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func bullet(from line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numbered(from line: String) -> (number: Int, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }
        let numberText = line[..<dotIndex]
        guard let number = Int(numberText) else {
            return nil
        }
        let textStart = line.index(after: dotIndex)
        guard textStart < line.endIndex, line[textStart] == " " else {
            return nil
        }
        let text = line[line.index(after: textStart)...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }
}
