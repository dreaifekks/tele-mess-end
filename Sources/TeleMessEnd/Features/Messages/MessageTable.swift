import SwiftUI

struct MessageTable: View {
    var messages: [CoreMessage]
    var tableMinHeight: CGFloat = 120
    var showMedia: ((CoreMessage) -> Void)?
    @State private var selection: CoreMessage.ID?

    var body: some View {
        VStack(spacing: 16) {
            Table(messages, selection: $selection) {
                TableColumn("Time") { message in
                    TimestampText(message.sentAt)
                }
                .width(min: 90, ideal: 120, max: 150)

                TableColumn("Chat") { message in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.displayChat)
                            .lineLimit(1)
                        Text(verbatim: "\(message.chatID) · \(message.accountID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 120, ideal: 160, max: 200)

                TableColumn("Sender") { message in
                    Text(message.displaySender)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 120, max: 150)

                TableColumn("Text") { message in
                    HStack(spacing: 8) {
                        if message.isDeleted {
                            StatusBadge(text: "Deleted", kind: .warning)
                        }
                        Text(message.text ?? "")
                            .lineLimit(3)
                    }
                }
                .width(min: 200)

                TableColumn("Media") { message in
                    HStack {
                        if message.hasMedia {
                            Button {
                                showMedia?(message)
                            } label: {
                                Label(mediaLabel(for: message), systemImage: "paperclip")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help(mediaLabel(for: message))
                        } else {
                            Text("")
                        }

                        if let url = message.telegramDeepLink {
                            Link(destination: url) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("Open in Telegram")
                        } else {
                            Text("")
                        }
                    }
                }
                .width(min: 50, ideal: 60, max: 70)
            }
            .frame(minHeight: tableMinHeight)

            if let selectedMessage = messages.first(where: { $0.id == selection }) {
                ScrollView {
                    Text(selectedMessage.text ?? "")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 160)
                .background(.regularMaterial)
            }
        }
    }

    private func mediaLabel(for message: CoreMessage) -> String {
        if let count = message.mediaCount, count > 0 {
            return "\(count)"
        }
        if let count = message.mediaFiles?.count, count > 0 {
            return "\(count)"
        }
        return "Media"
    }
}
