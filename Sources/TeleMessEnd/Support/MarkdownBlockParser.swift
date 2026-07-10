import Foundation

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(number: Int, text: String)
    case table(headers: [String], rows: [[String]])
    case quote(String)
    case code(String)
    case divider
}

enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var inCodeFence = false

        func flushParagraph() {
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        let lines = markdown.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeFence {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCodeFence = false
                } else {
                    flushParagraph()
                    inCodeFence = true
                }
                index += 1
                continue
            }

            if inCodeFence {
                codeLines.append(rawLine)
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if let table = table(startingAt: index, in: lines) {
                flushParagraph()
                blocks.append(.table(headers: table.headers, rows: table.rows))
                index = table.nextIndex
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if let bullet = bullet(from: trimmed) {
                flushParagraph()
                blocks.append(.bullet(bullet))
                index += 1
                continue
            }

            if let item = numbered(from: trimmed) {
                flushParagraph()
                blocks.append(.numbered(number: item.number, text: item.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        if inCodeFence {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }

    private static func table(startingAt index: Int, in lines: [String]) -> (headers: [String], rows: [[String]], nextIndex: Int)? {
        guard index + 1 < lines.count,
              let headers = tableCells(from: lines[index]),
              headers.count > 1,
              let separator = tableCells(from: lines[index + 1]),
              separator.count == headers.count,
              isTableSeparator(separator) else {
            return nil
        }

        var rows: [[String]] = []
        var current = index + 2
        while current < lines.count {
            guard let cells = tableCells(from: lines[current]), !isTableSeparator(cells) else {
                break
            }
            rows.append(normalizedTableCells(cells, count: headers.count))
            current += 1
        }

        return (headers: headers, rows: rows, nextIndex: current)
    }

    private static func tableCells(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        let hasBoundaryPipes = trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
        var content = trimmed
        if content.hasPrefix("|") {
            content.removeFirst()
        }
        if content.hasSuffix("|") {
            content.removeLast()
        }
        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard (cells.count > 1 || hasBoundaryPipes),
              cells.contains(where: { !$0.isEmpty }) else {
            return nil
        }
        return cells
    }

    private static func isTableSeparator(_ cells: [String]) -> Bool {
        cells.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: " ", with: "")
            return compact.contains("-") && compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func normalizedTableCells(_ cells: [String], count: Int) -> [String] {
        if cells.count == count {
            return cells
        }
        if cells.count > count {
            return Array(cells.prefix(count))
        }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else {
            return nil
        }
        let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func bullet(from line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numbered(from line: String) -> (number: Int, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }
        let numberText = line[..<dotIndex]
        guard let number = Int(numberText) else {
            return nil
        }
        let textStart = line.index(after: dotIndex)
        guard textStart < line.endIndex, line[textStart] == " " else {
            return nil
        }
        let text = line[line.index(after: textStart)...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }
}
