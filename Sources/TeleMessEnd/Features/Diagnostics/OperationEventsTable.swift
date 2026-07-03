import SwiftUI

struct OperationEventsTable: View {
    var events: [CoreOperationEvent]
    @Binding var selection: CoreOperationEvent.ID?

    var body: some View {
        Table(events, selection: $selection) {
            TableColumn("Time") { event in
                Text(DisplayFormat.shortDateTime(event.occurredAt))
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 180)

            TableColumn("Account") { event in
                Text(event.accountID)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Status") { event in
                StatusBadge(text: event.status, kind: event.status == "failed" ? .error : .warning)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Operation") { event in
                Text(event.operation)
                    .lineLimit(1)
            }

            TableColumn("Message") { event in
                Text(event.message ?? event.errorCode ?? "")
                    .lineLimit(2)
            }
        }
    }
}
