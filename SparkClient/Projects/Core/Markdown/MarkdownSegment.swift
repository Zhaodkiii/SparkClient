import Foundation

enum MarkdownSegment: Equatable, Sendable {
    struct TaskItem: Equatable, Sendable {
        let text: String
        let isDone: Bool
    }

    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList(items: [String])
    case orderedList(items: [String])
    case taskList(items: [TaskItem])
    case blockquote(lines: [String])
    case codeBlock(language: String?, code: String)
    case table(header: [String], rows: [[String]])
    case thematicBreak
}

enum MarkdownSegmentParser {
    static func parse(_ text: String) -> [MarkdownSegment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.isEmpty == false else { return [.paragraph("")] }

        var index = 0
        var result: [MarkdownSegment] = []
        result.reserveCapacity(max(8, lines.count / 2))

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                index += 1
                continue
            }

            if line.hasPrefix("```") {
                let (segment, nextIndex) = parseCodeBlock(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if isThematicBreak(line) {
                result.append(.thematicBreak)
                index += 1
                continue
            }

            if let heading = parseHeading(line) {
                result.append(heading)
                index += 1
                continue
            }

            if isTableHeader(lines: lines, at: index) {
                let (segment, nextIndex) = parseTable(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if line.hasPrefix(">") {
                let (segment, nextIndex) = parseBlockquote(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if parseTaskLine(line) != nil {
                let (segment, nextIndex) = parseTaskList(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if parseUnorderedListItem(line) != nil {
                let (segment, nextIndex) = parseUnorderedList(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            if parseOrderedListItem(line) != nil {
                let (segment, nextIndex) = parseOrderedList(lines: lines, start: index)
                result.append(segment)
                index = nextIndex
                continue
            }

            let (segment, nextIndex) = parseParagraph(lines: lines, start: index)
            result.append(segment)
            index = nextIndex
        }

        return result.isEmpty ? [.paragraph("")] : result
    }

    private static func parseCodeBlock(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        let opener = lines[start].trimmingCharacters(in: .whitespaces)
        let languageToken = opener.replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespaces)
        let language = languageToken.isEmpty ? nil : languageToken

        var index = start + 1
        var content: [String] = []
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                return (.codeBlock(language: language, code: content.joined(separator: "\n")), index + 1)
            }
            content.append(line)
            index += 1
        }
        return (.codeBlock(language: language, code: content.joined(separator: "\n")), index)
    }

    private static func parseHeading(_ line: String) -> MarkdownSegment? {
        let leadingHashes = line.prefix { $0 == "#" }.count
        guard (1 ... 6).contains(leadingHashes) else { return nil }
        let remainder = line.dropFirst(leadingHashes)
        guard remainder.first == " " else { return nil }
        return .heading(
            level: leadingHashes,
            text: remainder.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func parseBlockquote(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var quoteLines: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var body = trimmed.dropFirst()
            if body.first == " " { body = body.dropFirst() }
            quoteLines.append(String(body))
            index += 1
        }

        return (.blockquote(lines: quoteLines), index)
    }

    private static func parseTaskList(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var items: [MarkdownSegment.TaskItem] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let parsed = parseTaskLine(trimmed) else { break }
            items.append(parsed)
            index += 1
        }
        return (.taskList(items: items), index)
    }

    private static func parseUnorderedList(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var items: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = parseUnorderedListItem(trimmed) else { break }
            items.append(item)
            index += 1
        }
        return (.unorderedList(items: items), index)
    }

    private static func parseOrderedList(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var items: [String] = []

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = parseOrderedListItem(trimmed) else { break }
            items.append(item)
            index += 1
        }
        return (.orderedList(items: items), index)
    }

    private static func parseParagraph(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        var index = start
        var paragraphLines: [String] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || startsSpecialBlock(lines: lines, at: index) {
                break
            }
            paragraphLines.append(line)
            index += 1
        }

        return (.paragraph(paragraphLines.joined(separator: "\n")), index)
    }

    private static func isTableHeader(lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return header.contains("|") && isTableSeparator(separator)
    }

    private static func parseTable(lines: [String], start: Int) -> (MarkdownSegment, Int) {
        let header = splitTableRow(lines[start])
        var index = start + 2
        var rows: [[String]] = []

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.contains("|") == false {
                break
            }
            if startsSpecialBlock(lines: lines, at: index) {
                break
            }
            rows.append(splitTableRow(lines[index]))
            index += 1
        }
        return (.table(header: header, rows: rows), index)
    }

    private static func splitTableRow(_ row: String) -> [String] {
        var cells = row.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "|:- ")
        guard line.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return line.contains("-")
    }

    private static func parseTaskLine(_ line: String) -> MarkdownSegment.TaskItem? {
        guard line.count >= 6 else { return nil }
        guard line.hasPrefix("- [") || line.hasPrefix("* [") || line.hasPrefix("+ [") else { return nil }
        let chars = Array(line)
        guard chars.count >= 6, chars[3] == "]", chars[4] == " " else { return nil }
        let state = chars[2]
        guard state == " " || state == "x" || state == "X" else { return nil }
        let text = String(chars.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        return .init(text: text, isDone: state == "x" || state == "X")
    }

    private static func parseUnorderedListItem(_ line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func parseOrderedListItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let numberPart = line[..<dot]
        guard numberPart.isEmpty == false, numberPart.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line[line.index(after: dot)...]
        guard afterDot.first == " " else { return nil }
        return afterDot.trimmingCharacters(in: .whitespaces)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        if compact.allSatisfy({ $0 == "-" }) { return true }
        if compact.allSatisfy({ $0 == "*" }) { return true }
        if compact.allSatisfy({ $0 == "_" }) { return true }
        return false
    }

    private static func startsSpecialBlock(lines: [String], at index: Int) -> Bool {
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return true }
        if line.hasPrefix("```") { return true }
        if isThematicBreak(line) { return true }
        if parseHeading(line) != nil { return true }
        if line.hasPrefix(">") { return true }
        if parseTaskLine(line) != nil { return true }
        if parseUnorderedListItem(line) != nil { return true }
        if parseOrderedListItem(line) != nil { return true }
        if isTableHeader(lines: lines, at: index) { return true }
        return false
    }
}
