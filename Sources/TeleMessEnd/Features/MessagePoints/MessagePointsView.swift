import AppKit
import SwiftUI

struct MessagePointsView: View {
    @Bindable var model: AppModel
    @State private var selection: DailyMessagePoint.ID?
    @State private var loadedDetailIDs: Set<DailyMessagePoint.ID> = []
    @State private var sortOrder = [
        KeyPathComparator(\DailyMessagePoint.occurredAt, order: .reverse)
    ]

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                filters

                if model.dailyMessagePoints.isEmpty {
                    EmptyStateView(
                        title: "No message points",
                        detail: "Completed, persisted message points matching these filters appear here.",
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    pointsTable
                }
            }
            .padding(20)
            .frame(minWidth: 700, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            MessagePointDetailPanel(model: model, point: selectedPoint)
                .frame(width: 420)
                .frame(maxHeight: .infinity)
                .padding(.leading, 12)
        }
        .navigationTitle("Message Points")
        .disabled(model.isLoading)
        .task(id: model.sessionRevision) {
            selection = nil
            loadedDetailIDs.removeAll()
            sortOrder = [KeyPathComparator(\DailyMessagePoint.occurredAt, order: .reverse)]
        }
        .onChange(of: model.dailyMessagePoints.map(\.id)) {
            let currentIDs = Set(model.dailyMessagePoints.map(\.id))
            loadedDetailIDs.formIntersection(currentIDs)
            if let selection, !currentIDs.contains(selection) {
                self.selection = nil
            }
        }
        .onChange(of: selection) {
            loadSelectedDetailIfNeeded()
        }
        .onChange(of: model.messagePointImportanceMin) {
            if model.messagePointImportanceMax < model.messagePointImportanceMin {
                model.messagePointImportanceMax = model.messagePointImportanceMin
            }
        }
        .onChange(of: model.messagePointImportanceMax) {
            if model.messagePointImportanceMin > model.messagePointImportanceMax {
                model.messagePointImportanceMin = model.messagePointImportanceMax
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search content, origin, or importance reason", text: $model.messagePointSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(refresh)
                TextField("Date (YYYY-MM-DD)", text: $model.messagePointDateFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit(refresh)
                TextField("Tags (comma-separated)", text: $model.messagePointTagsFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .onSubmit(refresh)
                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            HStack(spacing: 10) {
                TextField("Account", text: $model.messagePointAccountFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .onSubmit(refresh)
                TextField("Origin ID", text: $model.messagePointOriginIDFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onSubmit(refresh)

                Picker("Min score", selection: $model.messagePointImportanceMin) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 118)

                Picker("Max score", selection: $model.messagePointImportanceMax) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 118)

                Picker("Origin", selection: $model.messagePointOriginImportanceFilter) {
                    ForEach(MessagePointOriginImportanceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)

                Button {
                    model.clearDailyMessagePointFilters()
                    refresh()
                } label: {
                    Label("Clear", systemImage: "line.3.horizontal.decrease.circle")
                }

                Spacer()
                Text("\(model.dailyMessagePoints.count) completed")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var pointsTable: some View {
        Table(sortedPoints, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Time", sortUsing: KeyPathComparator(\DailyMessagePoint.occurredAt)) { point in
                Text(DisplayFormat.shortDateTime(point.occurredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 135, ideal: 165)

            TableColumn("Origin", sortUsing: KeyPathComparator(\DailyMessagePoint.messagePointOriginSortValue)) { point in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if point.originImportant {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        Text(point.originTitle ?? "\(point.originID)")
                            .lineLimit(1)
                    }
                    Text(point.accountID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 150, ideal: 200)

            TableColumn("Tags", sortUsing: KeyPathComparator(\DailyMessagePoint.messagePointTagsSortValue)) { point in
                Text(point.tags.isEmpty ? "-" : point.tags.joined(separator: ", "))
                    .lineLimit(2)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Content", sortUsing: KeyPathComparator(\DailyMessagePoint.content)) { point in
                Text(point.content)
                    .lineLimit(3)
            }

            TableColumn("Score", sortUsing: KeyPathComparator(\DailyMessagePoint.importanceScore)) { point in
                Text("\(point.importanceScore)/5")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(scoreColor(point.importanceScore))
                    .help(point.importanceReason ?? "No importance reason recorded")
            }
            .width(min: 58, ideal: 68, max: 76)

            TableColumn("Link", sortUsing: KeyPathComparator(\DailyMessagePoint.messagePointTelegramSortValue)) { point in
                if let url = point.messagePointPreferredTelegramURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Open persisted Telegram address")
                }
            }
            .width(min: 44, ideal: 52, max: 60)
        }
    }

    private var selectedPoint: DailyMessagePoint? {
        guard let selection else { return nil }
        return model.dailyMessagePoints.first { $0.id == selection }
    }

    private var sortedPoints: [DailyMessagePoint] {
        model.dailyMessagePoints.sorted(using: sortOrder)
    }

    private func refresh() {
        Task { await model.loadDailyMessagePoints() }
    }

    private func loadSelectedDetailIfNeeded() {
        guard let point = selectedPoint, !loadedDetailIDs.contains(point.id) else { return }
        Task {
            if await model.loadDailyMessagePoint(point) {
                loadedDetailIDs.insert(point.id)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 5:
            .red
        case 4:
            .orange
        case 3:
            .yellow
        default:
            .secondary
        }
    }
}

private struct MessagePointDetailPanel: View {
    @Bindable var model: AppModel
    var point: DailyMessagePoint?

    var body: some View {
        Group {
            if let point {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(point)
                        metadata(point)
                        content(point)
                        importance(point)
                        telegram(point)
                        sourceReferences(point)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                EmptyStateView(
                    title: "Select a message point",
                    detail: "Pick a completed point to inspect its persisted content, importance, links, and source references.",
                    systemImage: "doc.text.magnifyingglass"
                )
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private func header(_ point: DailyMessagePoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(point.originTitle ?? "Message Point")
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                MessagePointScorePill(score: point.importanceScore)
            }
            HStack(spacing: 8) {
                if point.originImportant {
                    Label("Important origin", systemImage: "star.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label("Regular origin", systemImage: "star")
                        .foregroundStyle(.secondary)
                }
                Text(point.pointID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .font(.caption)
        }
    }

    private func metadata(_ point: DailyMessagePoint) -> some View {
        LazyVGrid(columns: detailColumns, alignment: .leading, spacing: 8) {
            MessagePointMetadataTile(title: "Occurred", value: DisplayFormat.shortDateTime(point.occurredAt))
            MessagePointMetadataTile(title: "Date / Timezone", value: "\(point.date) · \(point.timezone)")
            MessagePointMetadataTile(title: "Account", value: point.accountID)
            MessagePointMetadataTile(title: "Origin / Topic", value: "\(point.originID) / \(point.topicID)")
            MessagePointMetadataTile(title: "Message", value: point.messageID.map(String.init) ?? "-")
            MessagePointMetadataTile(title: "Provider", value: point.provider ?? "-")
        }
    }

    private func content(_ point: DailyMessagePoint) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Content")
                .font(.headline)
            Text(point.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if !point.tags.isEmpty {
                Text(point.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .textSelection(.enabled)
            }
        }
    }

    private func importance(_ point: DailyMessagePoint) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Importance reason")
                .font(.headline)
            Text(point.importanceReason?.nilIfBlank ?? "No importance reason recorded.")
                .foregroundStyle(point.importanceReason?.nilIfBlank == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func telegram(_ point: DailyMessagePoint) -> some View {
        if point.telegramDeeplink?.nilIfBlank != nil || point.permalink?.nilIfBlank != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Telegram")
                    .font(.headline)
                HStack(spacing: 10) {
                    if let url = point.messagePointPreferredTelegramURL {
                        Link(destination: url) {
                            Label("Open Telegram", systemImage: "paperplane")
                        }
                    }
                    if let permalink = point.permalink?.nilIfBlank,
                       let url = URL(string: permalink),
                       permalink != point.telegramDeeplink {
                        Link(destination: url) {
                            Label("Open Web Link", systemImage: "safari")
                        }
                    }
                    if let address = point.messagePointCopyAddress {
                        Button {
                            copy(address)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
                if let deepLink = point.telegramDeeplink?.nilIfBlank {
                    MessagePointAddressRow(title: "Deep link", value: deepLink)
                }
                if let permalink = point.permalink?.nilIfBlank {
                    MessagePointAddressRow(title: "Permalink", value: permalink)
                }
            }
        }
    }

    private func sourceReferences(_ point: DailyMessagePoint) -> some View {
        DisclosureGroup("Source references (\(point.sourceRefs.count))") {
            Text(JSONValue.array(point.sourceRefs).description)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    private var detailColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8, alignment: .leading),
            GridItem(.flexible(), spacing: 8, alignment: .leading)
        ]
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        model.statusMessage = "Telegram address copied"
        model.lastError = nil
    }
}

private struct MessagePointScorePill: View {
    var score: Int

    var body: some View {
        Text("\(score)/5")
            .font(.callout.monospacedDigit().weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .background(foregroundColor.opacity(0.14), in: Capsule())
    }

    private var foregroundColor: Color {
        switch score {
        case 5: .red
        case 4: .orange
        case 3: .yellow
        default: .secondary
        }
    }
}

private struct MessagePointMetadataTile: View {
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

private struct MessagePointAddressRow: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension DailyMessagePoint {
    var messagePointOriginSortValue: String {
        "\(accountID)|\(originTitle ?? "")|\(originID)|\(topicID)"
    }

    var messagePointTagsSortValue: String {
        tagsCSV ?? tags.joined(separator: ",")
    }

    var messagePointTelegramSortValue: String {
        telegramDeeplink ?? permalink ?? ""
    }

    var messagePointPreferredTelegramURL: URL? {
        [telegramDeeplink, permalink]
            .compactMap { $0?.nilIfBlank }
            .compactMap(URL.init(string:))
            .first
    }

    var messagePointCopyAddress: String? {
        permalink?.nilIfBlank ?? telegramDeeplink?.nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
