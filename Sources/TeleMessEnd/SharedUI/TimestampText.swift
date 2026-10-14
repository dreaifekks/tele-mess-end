import SwiftUI

struct TimestampText: View {
    var value: String?

    init(_ value: String?) {
        self.value = value
    }

    var body: some View {
        Text(DisplayFormat.shortDateTime(value))
            .font(.body)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}
