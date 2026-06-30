import Foundation

struct MedicalDocumentModelJSONNormalizer: Sendable {
    func normalizedModelJSONText(_ text: String) -> String {
        jsonCandidateString(from: text) ?? sanitizeModelJSONText(text)
    }

    func jsonCandidateString(from json: String) -> String? {
        let extracted = extractJSONFromMarkdownOrRaw(json)
        let sanitized = sanitizeModelJSONText(extracted)

        if let first = extractFirstCompleteJSON(from: sanitized),
           isValidJSON(first) {
            return first
        }

        // Fallback: some responses are plain JSON without extra wrappers.
        if isValidJSON(sanitized) { return sanitized }

        // Last-resort: try to repair mismatched braces/brackets caused by model
        // over-generating closing delimiters (e.g. `}}}` instead of `}`).
        if let repaired = repairUnbalancedDelimiters(sanitized), isValidJSON(repaired) {
            return repaired
        }

        return nil
    }

    private func sanitizeModelJSONText(_ text: String) -> String {
        let withoutCodeFence = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        let withoutCommentLines = withoutCodeFence
            .components(separatedBy: .newlines)
            .filter { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("//") == false
            }
            .joined(separator: "\n")

        return removeTrailingCommas(in: withoutCommentLines)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractJSONFromMarkdownOrRaw(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.contains("```") else { return result }

        guard let startRange = result.range(of: "```") else { return result }
        var startIndex = startRange.upperBound

        // Skip optional language label line (e.g. ```json).
        while startIndex < result.endIndex {
            if result[startIndex] == "\n" {
                startIndex = result.index(after: startIndex)
                break
            }
            startIndex = result.index(after: startIndex)
        }

        guard let endRange = result.range(of: "```", options: .backwards),
              endRange.lowerBound >= startIndex else {
            return String(result[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(result[startIndex..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeTrailingCommas(in text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()
        var current = iterator.next()
        var inString = false
        var isEscaped = false

        while let char = current {
            if inString {
                result.append(char)
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString = false
                }
                current = iterator.next()
                continue
            }

            if char == "\"" {
                inString = true
                result.append(char)
                current = iterator.next()
                continue
            }

            if char == "," {
                var whitespace = ""
                var lookahead = iterator.next()
                while let next = lookahead, next.isWhitespace {
                    whitespace.append(next)
                    lookahead = iterator.next()
                }
                if let next = lookahead, next == "}" || next == "]" {
                    result.append(whitespace)
                    result.append(next)
                    current = iterator.next()
                    continue
                }
                result.append(char)
                result.append(whitespace)
                current = lookahead
                continue
            }

            result.append(char)
            current = iterator.next()
        }
        return result
    }

    private func extractFirstCompleteJSON(from text: String) -> String? {
        guard let range = firstCompleteJSONRange(in: text) else { return nil }
        return String(text[range])
    }

    private func firstCompleteJSONRange(in text: String) -> Range<String.Index>? {
        var index = text.startIndex
        var started = false
        var startIndex: String.Index?
        var inString = false
        var escapeNext = false
        var braceCount = 0
        var bracketCount = 0

        while index < text.endIndex {
            let char = text[index]

            if !started {
                if char.isWhitespace {
                    index = text.index(after: index)
                    continue
                }
                startIndex = index
                started = true
            }

            if escapeNext {
                escapeNext = false
                index = text.index(after: index)
                continue
            }

            if char == "\\" && inString {
                escapeNext = true
                index = text.index(after: index)
                continue
            }

            if char == "\"" {
                inString.toggle()
                if !inString && braceCount == 0 && bracketCount == 0, let start = startIndex {
                    let end = text.index(after: index)
                    let candidate = String(text[start..<end])
                    if isValidJSON(candidate) { return start..<end }
                }
                index = text.index(after: index)
                continue
            }

            if inString {
                index = text.index(after: index)
                continue
            }

            switch char {
            case "{":
                braceCount += 1
            case "}":
                braceCount -= 1
            case "[":
                bracketCount += 1
            case "]":
                bracketCount -= 1
            default:
                break
            }

            if braceCount < 0 || bracketCount < 0 {
                return nil
            }

            if braceCount == 0 && bracketCount == 0, let start = startIndex {
                let end = text.index(after: index)
                let candidate = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidJSON(candidate) {
                    // Recalculate precise range against original text.
                    let segment = String(text[start..<end])
                    let leadingCount = segment.prefix(while: { $0.isWhitespace }).count
                    let trailingCount = segment.reversed().prefix(while: { $0.isWhitespace }).count
                    let adjustedStart = text.index(start, offsetBy: leadingCount)
                    let adjustedEnd = text.index(end, offsetBy: -trailingCount)
                    return adjustedStart..<adjustedEnd
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private func isValidJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    /// Removes extra (unbalanced) `}` / `]` characters that a model occasionally
    /// appends to an otherwise valid JSON payload. Characters inside strings are
    /// left untouched; only out-of-string closing delimiters that would push the
    /// depth counter below zero are dropped.
    private func repairUnbalancedDelimiters(_ text: String) -> String? {
        var result = ""
        result.reserveCapacity(text.count)
        var inString = false
        var isEscaped = false
        var braceDepth = 0
        var bracketDepth = 0

        for char in text {
            if inString {
                result.append(char)
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }

            switch char {
            case "\"":
                inString = true
                result.append(char)
            case "{":
                braceDepth += 1
                result.append(char)
            case "}":
                guard braceDepth > 0 else { continue } // drop extra `}`
                braceDepth -= 1
                result.append(char)
            case "[":
                bracketDepth += 1
                result.append(char)
            case "]":
                guard bracketDepth > 0 else { continue } // drop extra `]`
                bracketDepth -= 1
                result.append(char)
            default:
                result.append(char)
            }
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
