import SwiftUI

enum SetupStepState: Equatable {
    case pending
    case current
    case complete
    case problem
}

struct SetupStepRow<Content: View>: View {
    let number: Int
    let title: String
    let detail: String
    let status: String?
    let statusKind: StatusBadgeKind
    let markerState: SetupStepState
    let content: Content

    init(
        number: Int,
        title: String,
        detail: String,
        status: String? = nil,
        statusKind: StatusBadgeKind = .neutral,
        markerState: SetupStepState,
        @ViewBuilder content: () -> Content
    ) {
        self.number = number
        self.title = title
        self.detail = detail
        self.status = status
        self.statusKind = statusKind
        self.markerState = markerState
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            marker
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if let status {
                        StatusBadge(text: status, kind: statusKind)
                    }
                }

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                content
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var marker: some View {
        if markerState == .complete {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(StatusBadgeKind.success.tint)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Step \(number) complete")
        } else {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(markerForeground)
                .frame(width: 22, height: 22)
                .background(markerBackground, in: Circle())
                .overlay {
                    Circle()
                        .stroke(markerForeground.opacity(0.55), lineWidth: 1)
                }
                .accessibilityLabel("Step \(number)")
        }
    }

    private var markerForeground: Color {
        switch markerState {
        case .pending:
            .secondary
        case .current:
            .accentColor
        case .complete:
            StatusBadgeKind.success.tint
        case .problem:
            StatusBadgeKind.error.tint
        }
    }

    private var markerBackground: Color {
        markerForeground.opacity(0.12)
    }
}

extension SetupStepRow where Content == EmptyView {
    init(number: Int, title: String, detail: String, markerState: SetupStepState) {
        self.init(number: number, title: title, detail: detail, markerState: markerState) {
            EmptyView()
        }
    }
}
