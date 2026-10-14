import SwiftUI

struct MessagesView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Search messages", text: $model.messageSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await model.searchMessages() }
                    }
                Button {
                    Task { await model.searchMessages() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                Button {
                    model.messageSearchQuery = ""
                    Task { await model.loadRecentMessages() }
                } label: {
                    Label("Recent", systemImage: "clock")
                }
            }

            if model.messages.isEmpty {
                EmptyStateView(title: model.messagesAreSearchResults ? "No matching messages" : "No messages", detail: model.messagesAreSearchResults ? "" : "Load recent messages or run a full-text search.", systemImage: "text.bubble")
            } else {
                MessageTable(messages: model.messages) { message in
                    model.showMedia(for: message)
                }
            }
        }
        .padding(20)
        .navigationTitle("Messages")
    }
}
