import SwiftUI

struct AccountsView: View {
    @Bindable var model: AppModel
    @State private var selectedAccountID: CoreAccount.ID?
    @State private var tableSelection: CoreAccount.ID?
    @State private var isCreatingAccount = false
    @State private var isEditingPhone = false
    @State private var accountID = ""
    @State private var displayName = ""
    @State private var phone = ""
    @State private var sessionName = ""
    @State private var sessionDir = ""
    @State private var code = ""
    @State private var password = ""
    @State private var pendingDeleteAccount: CoreAccount?

    var body: some View {
        HSplitView {
            accountForm
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Accounts")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await model.loadAccounts() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }

                if model.accounts.isEmpty {
                    EmptyStateView(title: "No accounts", detail: "Create account metadata, then request a Telegram login code.", systemImage: "person.badge.plus")
                } else {
                    AccountsTable(accounts: model.accounts, selection: $tableSelection, activate: { account in
                        selectAccount(account)
                    }, requestDelete: { account in
                        pendingDeleteAccount = account
                    })
                }
            }
            .padding(20)
        }
        .navigationTitle("Accounts")
        .task {
            if model.accounts.isEmpty {
                await model.loadAccounts()
            }
            syncSelectionAfterAccountsChange()
        }
        .onChange(of: selectedAccountID) {
            if selectedAccountID != nil {
                isCreatingAccount = false
                tableSelection = selectedAccountID
            }
            loadSelectedAccount()
        }
        .onChange(of: model.accounts) {
            syncSelectionAfterAccountsChange()
        }
        .alert("Delete account metadata?", isPresented: Binding(
            get: { pendingDeleteAccount != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteAccount = nil
                }
            }
        )) {
            Button("Delete", role: .destructive) {
                if let account = pendingDeleteAccount {
                    Task {
                        await model.deleteAccount(account)
                        syncSelectionAfterAccountsChange()
                    }
                }
                pendingDeleteAccount = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAccount = nil
            }
        } message: {
            Text("This removes account management metadata through the core API. Archived messages remain unless the core changes that contract.")
        }
    }

    private var accountForm: some View {
        Form {
            Section {
                HStack {
                    Picker("Account", selection: $selectedAccountID) {
                        ForEach(model.accounts) { account in
                            Text(account.title).tag(Optional(account.id))
                        }
                    }
                    .disabled(model.accounts.isEmpty)
                    Spacer()
                    Button {
                        beginCreatingAccount()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add account")
                }
            }

            Section("Account") {
                if isCreatingAccount {
                    TextField("Account ID", text: $accountID)
                } else {
                    LabeledContent("Account ID") {
                        Text(accountID.isEmpty ? "-" : accountID)
                            .textSelection(.enabled)
                    }
                }
                TextField("Display name", text: $displayName)
                if isCreatingAccount || isEditingPhone || phone.isEmpty {
                    TextField("Phone", text: $phone)
                } else {
                    LabeledContent("Phone") {
                        HStack {
                            Text(DisplayFormat.maskedPhone(phone))
                            Button("Edit") {
                                isEditingPhone = true
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                TextField("Session name", text: $sessionName)
                TextField("Session directory", text: $sessionDir)
                Button {
                    Task {
                        let savedAccountID = accountID
                        await model.createAccount(
                            CreateAccountRequest(
                                accountID: accountID,
                                displayName: displayName.nilIfEmpty,
                                phone: phone.nilIfEmpty,
                                sessionName: sessionName.nilIfEmpty,
                                sessionDir: sessionDir.nilIfEmpty
                            )
                        )
                        selectedAccountID = model.accounts.first { $0.accountID == savedAccountID }?.id
                        isCreatingAccount = false
                        isEditingPhone = false
                    }
                } label: {
                    Label(isCreatingAccount ? "Add Account" : "Save Account", systemImage: "square.and.arrow.down")
                }
                .disabled(accountID.isEmpty)
            }

            Section("Telegram Auth") {
                TextField("Login code", text: $code)
                SecureField("2FA password", text: $password)
                HStack {
                    Button("Status") {
                        Task { await model.authStatus(accountID: accountID) }
                    }
                    .disabled(accountID.isEmpty)
                    Button("Request Code") {
                        Task { await model.requestCode(accountID: accountID, phone: phone) }
                    }
                    .disabled(accountID.isEmpty || phone.isEmpty)
                }
                Button {
                    Task {
                        await model.submitCode(accountID: accountID, phone: phone, code: code, password: password.nilIfEmpty)
                    }
                } label: {
                    Label("Submit Code", systemImage: "paperplane")
                }
                .disabled(accountID.isEmpty || phone.isEmpty || code.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func beginCreatingAccount() {
        selectedAccountID = nil
        isCreatingAccount = true
        isEditingPhone = true
        accountID = ""
        displayName = ""
        phone = ""
        sessionName = ""
        sessionDir = ""
    }

    private func loadSelectedAccount() {
        guard !isCreatingAccount,
              let selectedAccountID,
              let account = model.accounts.first(where: { $0.id == selectedAccountID }) else {
            return
        }
        accountID = account.accountID
        displayName = account.displayName ?? ""
        phone = account.phone ?? ""
        sessionName = account.sessionName ?? account.accountID
        sessionDir = account.sessionDir ?? ""
        isEditingPhone = false
    }

    private func selectAccount(_ account: CoreAccount) {
        isCreatingAccount = false
        selectedAccountID = account.id
        tableSelection = account.id
        accountID = account.accountID
        displayName = account.displayName ?? ""
        phone = account.phone ?? ""
        sessionName = account.sessionName ?? account.accountID
        sessionDir = account.sessionDir ?? ""
        isEditingPhone = false
    }

    private func syncSelectionAfterAccountsChange() {
        if isCreatingAccount { return }
        if let selectedAccountID,
           model.accounts.contains(where: { $0.id == selectedAccountID }) {
            tableSelection = selectedAccountID
            loadSelectedAccount()
            return
        }
        selectedAccountID = model.accounts.first?.id
        tableSelection = selectedAccountID
        loadSelectedAccount()
    }
}

private struct AccountsTable: View {
    var accounts: [CoreAccount]
    @Binding var selection: CoreAccount.ID?
    var activate: (CoreAccount) -> Void
    var requestDelete: (CoreAccount) -> Void

    var body: some View {
        Table(accounts, selection: $selection) {
            TableColumn("Account") { account in
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.title)
                        .lineLimit(1)
                    Text(account.accountID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    activate(account)
                }
            }
            TableColumn("Auth") { account in
                StatusBadge(text: account.authState ?? "unknown", kind: authBadgeKind(for: account))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        activate(account)
                    }
            }
            TableColumn("Session") { account in
                Text(account.sessionName ?? "")
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        activate(account)
                    }
            }
            TableColumn("Phone") { account in
                Text(DisplayFormat.maskedPhone(account.phone))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        activate(account)
                    }
            }
            TableColumn("Last Error") { account in
                Text(account.lastError ?? "")
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        activate(account)
                    }
            }
            TableColumn("Updated") { account in
                Text(DisplayFormat.shortDateTime(account.authUpdatedAt ?? account.updatedAt))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        activate(account)
                    }
            }
            TableColumn("Delete") { account in
                Button(role: .destructive) {
                    requestDelete(account)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
            .width(min: 54, ideal: 64, max: 72)
        }
    }

    private func authBadgeKind(for account: CoreAccount) -> StatusBadgeKind {
        if account.lastError != nil {
            return .error
        }
        switch (account.authState ?? "").lowercased() {
        case "authorized", "signed_in", "authenticated", "ready":
            return .success
        case "pending", "code_requested", "code_sent", "password_required", "2fa_required", "needs_code", "needs_password":
            return .warning
        case "unauthorized", "failed", "error":
            return .error
        default:
            return .neutral
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
