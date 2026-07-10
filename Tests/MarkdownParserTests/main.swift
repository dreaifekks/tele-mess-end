import Foundation

@main
enum MarkdownParserTests {
    static func main() throws {
        try expectEqual(
            MarkdownBlockParser.parse("# Title\n\n- one\n2. two\n> quote\n---"),
            [
                .heading(level: 1, text: "Title"),
                .bullet("one"),
                .numbered(number: 2, text: "two"),
                .quote("quote"),
                .divider
            ]
        )

        try expectEqual(
            MarkdownBlockParser.parse("| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 |"),
            [.table(headers: ["A", "B"], rows: [["1", "2"], ["3", ""]])]
        )

        try expectEqual(
            MarkdownBlockParser.parse("```swift\nlet value = 1"),
            [.code("let value = 1")]
        )

        print("Markdown parser tests passed")
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    guard actual == expected else {
        throw MarkdownParserTestError.failure("Expected \(expected), got \(actual)")
    }
}

private enum MarkdownParserTestError: Error, CustomStringConvertible {
    case failure(String)

    var description: String {
        switch self {
        case .failure(let message):
            message
        }
    }
}
