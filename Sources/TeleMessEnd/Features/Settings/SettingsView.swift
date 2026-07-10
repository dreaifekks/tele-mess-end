import Foundation
import SwiftUI

private struct SummarySettingsLoadKey: Hashable {
    var profileID: UUID?
    var sessionRevision: UInt64
    var section: SettingsSection
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var draft = CoreProfile.defaultLocal
    @State private var summaryDraft = SummarySettings()
    @State private var token = ""
    @State private var tokenWasEdited = false
    @State private var confirmDeleteProfile = false
    @State private var summaryOperationID: UUID?
    private let settingsAccent = Color(red: 0.38, green: 0.70, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneSwitcher(selection: $model.settingsSection, accent: settingsAccent)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider()

            switch model.settingsSection {
            case .core:
                coreSettings
                    .padding(24)
            case .summary:
                summarySettings
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .disabled(summaryOperationID != nil || model.isLoading)
            }
        }
        .frame(width: 920, height: 620)
        .tint(settingsAccent)
        .onAppear {
            loadDraft()
            loadSummaryDraftFromStore()
        }
        .onChange(of: model.sessionRevision) {
            loadDraft()
            loadSummaryDraftFromStore()
        }
        .task(id: SummarySettingsLoadKey(
            profileID: model.selectedProfile?.id,
            sessionRevision: model.sessionRevision,
            section: model.settingsSection
        )) {
            guard model.settingsSection == .summary else { return }
            await loadSummaryContext(replacingCurrent: true)
        }
        .alert("Delete profile?", isPresented: $confirmDeleteProfile) {
            Button("Delete", role: .destructive) {
                if model.deleteSelectedProfile() {
                    loadDraft()
                    loadSummaryDraftFromStore()
                }
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
                                if saveDraft() {
                                    model.startLocalCore()
                                }
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
                            if saveDraft() {
                                Task { await model.validateActiveProfile() }
                            }
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
                            draft = model.addRemoteProfile()
                            token = ""
                        } label: {
                            Label("Add Remote Core", systemImage: "plus")
                        }
                        Spacer()
                        Button {
                            draft = model.addLocalProfile()
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
                }

                PreferenceGroup(
                    title: "Scope",
                    help: "Scope filters which archived messages go into the daily package and summary. Empty fields include all matches; Important-only limits it to origins marked with the star."
                ) {
                    PreferenceRow(title: "Account ID") {
                        ScopeSingleSelectMenu(
                            selection: accountSelection,
                            placeholder: "Any account",
                            options: targetOptions.scopeAccountIDs.map { ScopePickerOption(value: $0, title: $0) }
                        )
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Origin ID") {
                        ScopeSingleSelectMenu(selection: originSelection, placeholder: "Any origin", options: targetOptions.scopeOrigins)
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Topic ID") {
                        ScopeSingleSelectMenu(selection: topicSelection, placeholder: "Any topic", options: targetOptions.scopeTopics)
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Tags") {
                        TagMultiSelectMenu(tagsText: $summaryDraft.tags, options: targetOptions.scopeTags)
                            .frame(width: 260)
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Important origins only") {
                        Toggle("", isOn: $summaryDraft.importantOnly)
                            .labelsHidden()
                    }
                }

                PreferenceGroup(
                    title: "Delivery",
                    help: "Delivery sends the final daily summary through the selected Telegram account to a selected group, channel, or forum topic."
                ) {
                    PreferenceRow(title: "Enable forwarding") {
                        Toggle("", isOn: $summaryDraft.deliveryEnabled)
                            .labelsHidden()
                    }
                    PreferenceDivider()
                    PreferenceRow(title: "Sender account") {
                        HStack(spacing: 8) {
                            ScopeSingleSelectMenu(
                                selection: deliveryAccountSelection,
                                placeholder: "Select account",
                                options: targetOptions.deliveryAccounts
                            )
                            Button {
                                Task { await discoverDeliveryTargets() }
                            } label: {
                                Label("Discover", systemImage: "arrow.clockwise")
                            }
                            .labelStyle(.iconOnly)
                            .help("Discover groups and topics for this account")
                            .disabled(!summaryDraft.deliveryEnabled || summaryDraft.deliveryAccountID.isEmpty)
                        }
                    }
                    .disabled(!summaryDraft.deliveryEnabled)
                    PreferenceDivider()
                    PreferenceRow(title: "Group or channel") {
                        ScopeSingleSelectMenu(
                            selection: deliveryOriginSelection,
                            placeholder: "Select group",
                            options: targetOptions.deliveryOrigins
                        )
                    }
                    .disabled(!summaryDraft.deliveryEnabled || summaryDraft.deliveryAccountID.isEmpty)
                    PreferenceDivider()
                    PreferenceRow(title: "Topic") {
                        ScopeSingleSelectMenu(
                            selection: deliveryTopicSelection,
                            placeholder: "Group root",
                            options: targetOptions.deliveryTopics
                        )
                    }
                    .disabled(!summaryDraft.deliveryEnabled || summaryDraft.deliveryOriginID.isEmpty)
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
                        .disabled(!summaryDraftCanSave)
                        Button {
                            Task { await loadSummaryContext() }
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

    @discardableResult
    private func saveDraft() -> Bool {
        let succeeded = model.saveProfile(draft, token: tokenWasEdited ? token : nil)
        if succeeded {
            tokenWasEdited = false
        }
        return succeeded
    }

    private func loadDraft() {
        draft = model.selectedProfile ?? .defaultLocal
        token = ""
        tokenWasEdited = false
    }

    private func saveSummaryDraft() async {
        guard summaryOperationID == nil, !model.isLoading else { return }
        let operationID = UUID()
        summaryOperationID = operationID
        defer {
            if summaryOperationID == operationID {
                summaryOperationID = nil
            }
        }
        if await model.saveSummarySchedule(summaryDraft), !Task.isCancelled {
            loadSummaryDraftFromStore()
        }
    }

    private func loadSummaryContext(replacingCurrent: Bool = false) async {
        guard replacingCurrent || summaryOperationID == nil else { return }
        let operationID = UUID()
        summaryOperationID = operationID
        defer {
            if summaryOperationID == operationID {
                summaryOperationID = nil
            }
        }

        while model.isLoading {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
        guard !Task.isCancelled,
              model.settingsSection == .summary else { return }
        let profileID = model.selectedProfile?.id
        guard await model.loadSummarySchedule(),
              !Task.isCancelled,
              model.selectedProfile?.id == profileID else { return }
        loadSummaryDraftFromStore()
        await model.loadSummaryScopeOptions()
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

    private var deliveryAccountSelection: Binding<String> {
        Binding(
            get: { summaryDraft.deliveryAccountID },
            set: { value in
                summaryDraft.deliveryAccountID = value
                summaryDraft.deliveryOriginID = ""
                summaryDraft.deliveryTopicID = ""
            }
        )
    }

    private var deliveryOriginSelection: Binding<String> {
        Binding(
            get: { summaryDraft.deliveryOriginID },
            set: { value in
                summaryDraft.deliveryOriginID = value
                summaryDraft.deliveryTopicID = ""
            }
        )
    }

    private var deliveryTopicSelection: Binding<String> {
        Binding(
            get: { summaryDraft.deliveryTopicID },
            set: { summaryDraft.deliveryTopicID = $0 }
        )
    }

    private var summaryDraftCanSave: Bool {
        !summaryDraft.deliveryEnabled ||
            (!summaryDraft.deliveryAccountID.isEmpty && Int(summaryDraft.deliveryOriginID) != nil)
    }

    private var targetOptions: SummaryTargetOptions {
        SummaryTargetOptions(accounts: model.summaryScopeAccounts, origins: model.summaryScopeOrigins, draft: summaryDraft)
    }

    private func discoverDeliveryTargets() async {
        guard !summaryDraft.deliveryAccountID.isEmpty else { return }
        await model.discoverSummaryScopeOptions(accountID: summaryDraft.deliveryAccountID)
    }

}

private struct SettingsPaneSwitcher: View {
    @Binding var selection: SettingsSection
    var accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(SettingsSection.allCases) { pane in
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
