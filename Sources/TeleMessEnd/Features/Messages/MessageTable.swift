import SwiftUI

struct MessageTable: View {
    var messages: [CoreMessage]

    var body: some View {
        Table(messages) {
            TableColumn("Time") { message in
                Text(DisplayFormat.shortDateTime(message.sentAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Account") { message in
                Text(message.accountID)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Chat") { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.displayChat)
                        .lineLimit(1)
                    Text("\(message.chatID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 160, ideal: 220)

            TableColumn("Sender") { message in
                Text(message.displaySender)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 160)

            TableColumn("Text") { message in
                HStack(spacing: 8) {
                    if message.isDeleted {
                        StatusBadge(text: "Deleted", kind: .warning)
                    }
                    if message.hasMedia {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                    }
                    Text(message.text ?? "")
                        .lineLimit(3)
                }
            }

            TableColumn("Link") { message in
                if let permalink = message.permalink,
                   let url = URL(string: permalink) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                } else {
                    Text("")
                }
            }
            .width(min: 48, ideal: 56, max: 64)
        }
    }
}
