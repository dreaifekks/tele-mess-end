import SwiftUI

struct MetricCard: View {
    var title: String
    var value: String
    var detail: String?
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
