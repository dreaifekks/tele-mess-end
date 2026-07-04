import Foundation
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var settingsPane: SettingsPane = .core
    @State private var draft = CoreProfile.defaultLocal
    @State private var summaryDraft = SummarySettings()
    @State private var token = ""
    @State private var tokenWasEdited = false
    @State private var confirmDeleteProfile = false
    private let settingsAccent = Color(red: 0.38, green: 0.70, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneSwitcher(selection: $settingsPane, accent: settingsAccent)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider()

            switch settingsPane {
            case .core:
                coreSettings
                    .padding(24)
            case .summary:
                summarySettings
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
            }
        }
        .frame(width: 920, height: 620)
        .tint(settingsAccent)
        .onAppear {
            loadDraft()
            loadSummaryDraft()
            Task { await loadSummaryScopeOptionsIfNeeded() }
        }
        .onChange(of: model.profileStore.selectedProfileID) {
            loadDraft()
        }
        .onChange(of: settingsPane) {
            if settingsPane == .summary {
                Task { await loadSummaryScopeOptionsIfNeeded() }
            }
        }
        .alert("Delete profile?", isPresented: $confirmDeleteProfile) {
            Button("Delete", role: .destructive) {
                model.deleteSelectedProfile()
                loadDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected local app profile and its stored token. It does not change the core service.")
        }
    }

    private var coreSettings: some View {
        HSplitView {
            List(selection: Binding<UUID?>(
                get: { model.profileStore.selectedProfileID },
                set: { model.selectProfile($0) }
            )) {
                ForEach(model.profileStore.profiles) { profile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.body.weight(.semibold))
                        Text(profile.kind.title)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .tag(Optional(profile.id))
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

            Form {
                Section("Connection") {
                    TextField("Name", text: $draft.name)
                    Picker("Mode", selection: $draft.kind) {
                        ForEach(CoreProfileKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Base URL", text: $draft.baseURLString)
                    Picker("Auth", selection: $draft.authMode) {
                        ForEach(CoreAuthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    HStack {
                        SecureField("New API token", text: Binding(
                            get: { token },
                            set: { value in
                                token = value
                                tokenWasEdited = true
                            }
                        ))
                        Button {
                            token = ""
                            tokenWasEdited = true
                        } label: {
                            Label("Clear Token", systemImage: "key.slash")
                        }
                    }
                }

                if draft.kind == .local {
                    Section("Local Runtime") {
                        TextField("Command", text: $draft.localCommand)
                        TextField("Working directory", text: $draft.localWorkingDirectory)
                        HStack {
                            Button {
                                saveDraft()
                                model.startLocalCore()
                            } label: {
                                Label("Start", systemImage: "play")
                            }
                            Button {
                                model.stopLocalCore()
                            } label: {
                                Label("Stop", systemImage: "stop")
                            }
                            .disabled(!model.localRunner.isRunning)
                            StatusBadge(text: model.localRunner.isRunning ? "Running" : "Stopped", kind: model.localRunner.isRunning ? .success : .neutral)
                        }
                        if let error = model.localRunner.lastError {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                        ScrollView {
                            Text(model.localRunner.lastOutput.isEmpty ? "No output yet." : model.localRunner.lastOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(minHeight: 110)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Section("Actions") {
                    HStack {
                        Button {
                            saveDraft()
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        Button {
                            saveDraft()
                            Task { await model.validateActiveProfile() }
                        } label: {
                            Label("Test Connection", systemImage: "network")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            confirmDeleteProfile = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(model.profileStore.profiles.count <= 1)
                    }

                    HStack {
                        Button {
                            draft = model.profileStore.addRemoteProfile()
                            token = ""
                        } label: {
                            Label("Add Remote Core", systemImage: "plus")
                        }
                        Spacer()
                        Button {
                            draft = model.profileStore.addLocalProfile()
                            token = ""
                        } label: {
                            Label("Add Local Core", systemImage: "plus")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.large)
            .font(.body)
            .frame(minWidth: 540)
            .padding(.leading, 18)
        }
            .frame(maxHeight: .infinity)
    }

    private var summarySettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreferenceGroup(title: "Schedule") {
                    PreferenceRow(title: "Enable daily group summary") {
                        Toggle("", isOn: $summaryDraft.enabled)
                            .labelsHidden()
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Run at") {
                        HStack(spacing: 10) {
                            TimeStepper(title: "Hour", value: $summaryDraft.scheduleHour, range: 0...23)
                            Text(":")
                                .font(.title2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                            TimeStepper(title: "Minute", value: $summaryDraft.scheduleMinute, range: 0...59)
                            TextField("Timezone", text: $summaryDraft.timezone)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 170)
                        }
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Lookback") {
                        ValueStepper(value: $summaryDraft.lookbackHours, range: 1...168, suffix: "hours")
                    }
                }

                PreferenceGroup(
                    title: "Scope",
                    help: "Scope filters which archived messages go into the daily package and summary. Empty fields include all matches; Important-only limits it to origins marked with the star."
                ) {
                    PreferenceRow(title: "Account ID") {
                        ScopeSingleSelectMenu(
                            selection: accountSelection,
                            placeholder: "Any account",
                            options: scopeAccountOptions.map { ScopePickerOption(value: $0, title: $0) }
                        )
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Origin ID") {
                        ScopeSingleSelectMenu(selection: originSelection, placeholder: "Any origin", options: scopeOriginOptions)
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Topic ID") {
                        ScopeSingleSelectMenu(selection: topicSelection, placeholder: "Any topic", options: scopeTopicOptions)
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Tags") {
                        TagMultiSelectMenu(tagsText: $summaryDraft.tags, options: scopeTagOptions)
                            .frame(width: 260)
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Important origins only") {
                        Toggle("", isOn: $summaryDraft.importantOnly)
                            .labelsHidden()
                    }
                }

                PreferenceGroup(title: "System Schedule") {
                    PreferenceRow(title: "System manager") {
                        TextField("systemd-user", text: $summaryDraft.systemManager)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                    }
                    PreferenceDivider()
                    PreferenceRow(
                        title: "Activate Systemd timer",
                        help: "When this is on, Save asks core to install or update the timer. Loaded values reflect core's installed state."
                    ) {
                        Toggle("", isOn: $summaryDraft.activateSystemd)
                            .labelsHidden()
                    }
                }

                PreferenceGroup(title: "Actions") {
                    HStack(spacing: 10) {
                        Button {
                            Task { await saveSummaryDraft() }
                        } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                        Button {
                            Task { await loadSummarySchedule() }
                        } label: {
                            Label("Load From Core", systemImage: "arrow.down.circle")
                        }
                        Button {
                            loadSummaryDraftFromStore()
                        } label: {
                            Label("Revert", systemImage: "arrow.uturn.backward")
                        }
                        Spacer()
                        StatusBadge(text: summaryDraft.enabled ? "\(summaryDraft.scheduleText) \(summaryDraft.timezone)" : "Off", kind: summaryDraft.enabled ? .success : .neutral)
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 20)
        }
    }

    private func saveDraft() {
        model.saveProfile(draft, token: tokenWasEdited ? token : nil)
        tokenWasEdited = false
    }

    private func loadDraft() {
        draft = model.selectedProfile ?? .defaultLocal
        token = ""
        tokenWasEdited = false
    }

    private func saveSummaryDraft() async {
        await model.saveSummarySchedule(summaryDraft)
        loadSummaryDraftFromStore()
    }

    private func loadSummaryDraft() {
        loadSummaryDraftFromStore()
        Task { await loadSummarySchedule() }
    }

    private func loadSummarySchedule() async {
        await model.loadSummarySchedule()
        loadSummaryDraftFromStore()
    }

    private func loadSummaryScopeOptionsIfNeeded() async {
        if model.accounts.isEmpty || model.origins.isEmpty {
            await model.loadSummaryScopeOptions()
        }
    }

    private func loadSummaryDraftFromStore() {
        summaryDraft = model.summarySettingsStore.settings
    }

    private var accountSelection: Binding<String> {
        Binding(
            get: { summaryDraft.accountID },
            set: { value in
                summaryDraft.accountID = value
                summaryDraft.originID = ""
                summaryDraft.topicID = ""
            }
        )
    }

    private var originSelection: Binding<String> {
        Binding(
            get: { summaryDraft.originID },
            set: { value in
                summaryDraft.originID = value
                summaryDraft.topicID = ""
            }
        )
    }

    private var topicSelection: Binding<String> {
        Binding(
            get: { summaryDraft.topicID },
            set: { summaryDraft.topicID = $0 }
        )
    }

    private var scopeAccountOptions: [String] {
        Array(Set(model.accounts.map(\.accountID) + model.origins.map(\.accountID))).sorted()
    }

    private var scopeOriginOptions: [ScopePickerOption] {
        let rows = model.origins.filter { origin in
            summaryDraft.accountID.isEmpty || origin.accountID == summaryDraft.accountID
        }
        var grouped: [Int: CoreOrigin] = [:]
        for origin in rows {
            if grouped[origin.originID] == nil || !origin.isTopic {
                grouped[origin.originID] = origin
            }
        }
        return grouped.values
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            .map { origin in
                ScopePickerOption(
                    value: String(origin.originID),
                    title: "\(origin.displayTitle)  \(origin.originID)"
                )
            }
    }

    private var scopeTopicOptions: [ScopePickerOption] {
        var seen = Set<String>()
        return model.origins
            .filter { origin in
                origin.isTopic &&
                (summaryDraft.accountID.isEmpty || origin.accountID == summaryDraft.accountID) &&
                (summaryDraft.originID.isEmpty || String(origin.originID) == summaryDraft.originID)
            }
            .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            .compactMap { origin in
                let value = String(origin.topicID)
                guard seen.insert(value).inserted else { return nil }
                return ScopePickerOption(
                    value: value,
                    title: "\(origin.displayTitle)  \(origin.topicID)"
                )
            }
    }

    private var scopeTagOptions: [String] {
        let tags = model.origins.flatMap { origin in
            Self.splitTags(origin.backupPolicy?.tags ?? "")
        }
        return Array(Set(tags)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func splitTags(_ value: String) -> [String] {
        value
            .split { character in
                character == "," || character == ";" || character == " " || character == "\n" || character == "\t"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ScopePickerOption: Identifiable, Hashable {
    var value: String
    var title: String
    var id: String { value }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case core
    case summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core:
            "Core Settings"
        case .summary:
            "Summary Settings"
        }
    }

    var label: String {
        switch self {
        case .core:
            "Core"
        case .summary:
            "Summary"
        }
    }

    var systemImage: String {
        switch self {
        case .core:
            "server.rack"
        case .summary:
            "text.badge.star"
        }
    }
}

private struct SettingsPaneSwitcher: View {
    @Binding var selection: SettingsPane
    var accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(SettingsPane.allCases) { pane in
                Button {
                    selection = pane
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: pane.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                        Text(pane.label)
                            .font(.callout.weight(.semibold))
                    }
                    .foregroundStyle(selection == pane ? accent : .secondary)
                    .frame(width: 82, height: 48)
                    .background(selection == pane ? accent.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selection == pane ? accent.opacity(0.75) : Color.clear, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PreferenceGroup<Content: View>: View {
    var title: String
    var help: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                if let help {
                    HelpPopoverButton(text: help)
                }
            }
            VStack(spacing: 0) {
                content
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct PreferenceRow<Trailing: View>: View {
    var title: String
    var help: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.body.weight(.medium))
                if let help {
                    HelpPopoverButton(text: help)
                }
            }
            Spacer(minLength: 24)
            trailing
                .frame(maxWidth: 430, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }
}

private struct HelpPopoverButton: View {
    var text: String
    @State private var isPresented = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { hovering in
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        isPresented = true
                    }
                }
            } else {
                isPresented = false
            }
        }
        .onDisappear {
            hoverTask?.cancel()
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(12)
        }
    }
}

private struct ScopeSingleSelectMenu: View {
    @Binding var selection: String
    var placeholder: String
    var options: [ScopePickerOption]

    var body: some View {
        Menu {
            Button(placeholder) {
                selection = ""
            }
            if !options.isEmpty {
                Divider()
                ForEach(options) { option in
                    Button {
                        selection = option.value
                    } label: {
                        HStack {
                            if selection == option.value {
                                Image(systemName: "checkmark")
                            }
                            Text(option.title)
                        }
                    }
                }
            }
        } label: {
            ScopeMenuLabel(title: title)
        }
        .buttonStyle(.plain)
        .frame(width: 260)
    }

    private var title: String {
        if selection.isEmpty {
            return placeholder
        }
        return options.first { $0.value == selection }?.title ?? selection
    }
}

private struct TagMultiSelectMenu: View {
    @Binding var tagsText: String
    var options: [String]

    var body: some View {
        Menu {
            if options.isEmpty {
                Text("No tags loaded")
            } else {
                ForEach(options, id: \.self) { tag in
                    Button {
                        toggle(tag)
                    } label: {
                        HStack {
                            if selectedTags.contains(tag) {
                                Image(systemName: "checkmark")
                            }
                            Text(tag)
                        }
                    }
                }
                Divider()
                Button("Clear") {
                    tagsText = ""
                }
            }
        } label: {
            ScopeMenuLabel(title: title)
        }
        .buttonStyle(.plain)
        .frame(width: 260)
    }

    private var selectedTags: Set<String> {
        Set(Self.split(tagsText))
    }

    private var title: String {
        let tags = Self.split(tagsText)
        if tags.isEmpty {
            return "Any tags"
        }
        if tags.count <= 2 {
            return tags.joined(separator: ", ")
        }
        return "\(tags.count) tags"
    }

    private func toggle(_ tag: String) {
        var tags = selectedTags
        if tags.contains(tag) {
            tags.remove(tag)
        } else {
            tags.insert(tag)
        }
        tagsText = tags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.joined(separator: ",")
    }

    private static func split(_ value: String) -> [String] {
        value
            .split { character in
                character == "," || character == ";" || character == " " || character == "\n" || character == "\t"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ScopeMenuLabel: View {
    var title: String

    var body: some View {
        HStack {
            Text(title)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(width: 260, height: 28)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct PreferenceDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
    }
}

private struct TimeStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%02d", value))
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
            .frame(width: 48, alignment: .trailing)
        }
        .controlSize(.small)
        .frame(width: 105)
    }
}

private struct ValueStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var suffix: String

    var body: some View {
        Stepper(value: $value, in: range) {
            Text("\(value) \(suffix)")
                .font(.body.monospacedDigit().weight(.medium))
                .frame(width: 118, alignment: .trailing)
        }
        .controlSize(.small)
        .frame(width: 160)
    }
}
