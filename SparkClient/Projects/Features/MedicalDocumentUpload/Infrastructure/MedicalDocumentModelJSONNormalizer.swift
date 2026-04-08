import Foundation

struct MedicalDocumentModelJSONNormalizer: Sendable {
    func normalizedModelJSONText(_ text: String) -> String {
        jsonCandidateString(from: text) ?? sanitizeModelJSONText(text)
    }

    func jsonCandidateString(from json: String) -> String? {
        let sanitized = sanitizeModelJSONText(json)
        return extractFirstJSONObject(from: sanitized)
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

    private func extractFirstJSONObject(from text: String) -> String? {
        let characters = Array(text)
        guard let startIndex = characters.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false

        for index in startIndex..<characters.count {
            let char = characters[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }

            if char == "\"" {
                inString = true
                continue
            }
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(characters[startIndex...index])
                }
            }
        }
        return nil
    }
}
