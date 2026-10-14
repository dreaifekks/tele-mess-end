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
        VStack(alignment: .leading, spacing: 16) {
            filters.fixedSize(horizontal: false, vertical: true)
            AdaptiveDetailLayout(hasDetail: selectedPoint != nil) {
                if model.dailyMessagePoints.isEmpty {
                    EmptyStateView(
                        title: "No message points",
                        detail: "Completed, persisted message points matching these filters appear here.",
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    pointsTable
                }
            } detail: {
                MessagePointDetailPanel(model: model, point: selectedPoint)
            }
        }
        .padding(20)
        .navigationTitle("Message Points")
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
                    .frame(width: UILayout.standardField)
                    .onSubmit(refresh)
                TextField("Tags (comma-separated)", text: $model.messagePointTagsFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: UILayout.standardField)
                    .onSubmit(refresh)
            }

            HStack(spacing: 10) {
                TextField("Account", text: $model.messagePointAccountFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: UILayout.standardField)
                    .onSubmit(refresh)
                TextField("Origin ID", text: $model.messagePointOriginIDFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: UILayout.compactField)
                    .onSubmit(refresh)

                Picker("Min score", selection: $model.messagePointImportanceMin) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: UILayout.compactField)

                Picker("Max score", selection: $model.messagePointImportanceMax) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: UILayout.compactField)

            }
            HStack(spacing: 10) {
                Picker("Origin", selection: $model.messagePointOriginImportanceFilter) {
                    ForEach(MessagePointOriginImportanceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: UILayout.standardField)

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
                TimestampText(point.occurredAt)
            }
            .width(min: 135, ideal: 165)

            TableColumn("Origin", sortUsing: KeyPathComparator(\DailyMessagePoint.messagePointOriginSortValue)) { point in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if point.originImportant {
                            Image(systemName: "star.fill")
                                .foregroundStyle(StatusBadgeKind.warning.tint)
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
            StatusBadgeKind.error.tint
        case 4:
            StatusBadgeKind.warning.tint
        case 3:
            StatusBadgeKind.warning.tint
        default:
            .secondary
        }
    }
}

private struct MessagePointDetailPanel: View {
    @Bindable var model: AppModel
    var point: DailyMessagePoint?

    var body: some View {
        DetailPanel {
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
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
                        .foregroundStyle(StatusBadgeKind.warning.tint)
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
            MetadataTile(title: "Occurred") { TimestampText(point.occurredAt) }
            MetadataTile(title: "Date / Timezone", value: "\(point.date) · \(point.timezone)")
            MetadataTile(title: "Account", value: point.accountID)
            MetadataTile(title: "Origin / Topic", value: "\(point.originID) / \(point.topicID)")
            MetadataTile(title: "Message", value: point.messageID.map(String.init) ?? "-")
            MetadataTile(title: "Provider", value: point.provider ?? "-")
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
            Text(point.importanceReason?.nilIfEmpty ?? "No importance reason recorded.")
                .foregroundStyle(point.importanceReason?.nilIfEmpty == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func telegram(_ point: DailyMessagePoint) -> some View {
        if point.telegramDeeplink?.nilIfEmpty != nil || point.permalink?.nilIfEmpty != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Telegram")
                    .font(.headline)
                HStack(spacing: 10) {
                    if let url = point.messagePointPreferredTelegramURL {
                        Link(destination: url) {
                            Label("Open Telegram", systemImage: "paperplane")
                        }
                    }
                    if let permalink = point.permalink?.nilIfEmpty,
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
                if let deepLink = point.telegramDeeplink?.nilIfEmpty {
                    MessagePointAddressRow(title: "Deep link", value: deepLink)
                }
                if let permalink = point.permalink?.nilIfEmpty {
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
        case 5: StatusBadgeKind.error.tint
        case 4: StatusBadgeKind.warning.tint
        case 3: StatusBadgeKind.warning.tint
        default: .secondary
        }
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
            .compactMap { $0?.nilIfEmpty }
            .compactMap(URL.init(string:))
            .first
    }

    var messagePointCopyAddress: String? {
        permalink?.nilIfEmpty ?? telegramDeeplink?.nilIfEmpty
    }
}
