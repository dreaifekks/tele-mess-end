import SwiftUI

struct RawPayloadView: View {
    var title: String
    var payload: JSONValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ScrollView {
                Text(payloadText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var payloadText: String {
        guard let payload else {
            return "No raw payload for the selected row."
        }
        if let data = try? JSONEncoder.pretty.encode(payload),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return payload.description
    }
}
