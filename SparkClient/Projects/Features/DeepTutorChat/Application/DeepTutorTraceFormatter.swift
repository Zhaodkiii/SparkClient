import Foundation

nonisolated enum DeepTutorTraceFormatter {
    static func tracePayload(
        from events: [DeepTutorStreamEvent],
        isStreaming: Bool,
        finalContent: String,
        previous: DeepTutorTraceBlockPayload? = nil
    ) -> DeepTutorTraceBlockPayload {
        let rows = rows(from: events)
        let hasFailure = rows.contains { $0.status == .failed }
        let isFinalAnswerPhase = isFinalAnswerPhase(
            events: events,
            isStreaming: isStreaming,
            finalContent: finalContent
        )
        let title: String
        if isStreaming {
            title = streamingTitle(for: rows)
        } else if hasFailure {
            title = "失败"
        } else {
            title = "已完成"
        }
        let autoExpanded = rows.isEmpty == false && isFinalAnswerPhase == false
        return DeepTutorTraceBlockPayload(
            title: title,
            rows: rows,
            isExpanded: autoExpanded,
            isStreaming: isStreaming,
            isFinalAnswerPhase: isFinalAnswerPhase,
            elapsedSeconds: previous?.elapsedSeconds ?? estimatedDuration(from: events)
        )
    }

    static func isFinalAnswerPhase(
        events: [DeepTutorStreamEvent],
        isStreaming: Bool,
        finalContent: String
    ) -> Bool {
        if hasPendingAskUser(events) {
            return false
        }
        if isStreaming == false {
            return true
        }
        if finalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }
        if events.contains(where: {
            if case .result = $0 { return true }
            return false
        }) {
            return true
        }
        return false
    }

    static func hasPendingAskUser(_ events: [DeepTutorStreamEvent]) -> Bool {
        var pendingToolCallID: String?
        for event in events {
            switch event {
            case let .askUser(_, toolCallID):
                pendingToolCallID = toolCallID
            case let .askUserResolved(toolCallID, _):
                if pendingToolCallID == toolCallID {
                    pendingToolCallID = nil
                }
            default:
                continue
            }
        }
        return pendingToolCallID != nil
    }

    static func streamingTitle(for rows: [DeepTutorTraceRowModel]) -> String {
        if let last = rows.last,
           last.status == .running,
           last.kind == .tool || last.kind == .askUser {
            return "调用工具中…"
        }
        return "DeepTutor 推理中…"
    }

    static func rows(from events: [DeepTutorStreamEvent]) -> [DeepTutorTraceRowModel] {
        var rows: [DeepTutorTraceRowModel] = []
        var toolIndexByCallID: [String: Int] = [:]
        var currentThinkingCallID: String?
        var currentThinkingText = ""

        func flushThinking() {
            let trimmed = currentThinkingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                currentThinkingText = ""
                currentThinkingCallID = nil
                return
            }
            let rowID = currentThinkingCallID ?? "thinking-\(rows.count)"
            rows.append(
                DeepTutorTraceRowModel(
                    id: rowID,
                    kind: .thinking,
                    icon: DeepTutorTraceGlyph.reasoning.rawValue,
                    verb: "",
                    status: .completed,
                    resultDetail: trimmed,
                    resultIsMarkdown: true
                )
            )
            currentThinkingText = ""
            currentThinkingCallID = nil
        }

        for event in events {
            switch event {
            case let .reasoningDelta(text, callID, _):
                let cid = callID ?? "reasoning"
                if currentThinkingCallID != cid {
                    flushThinking()
                    currentThinkingCallID = cid
                }
                currentThinkingText += text

            case let .toolCallStarted(callID, toolName, argsSummary):
                flushThinking()
                let descriptor = describeTool(toolName: toolName, argsSummary: argsSummary)
                let row = DeepTutorTraceRowModel(
                    id: callID,
                    kind: DeepTutorAskUserNormalizer.isAskUserTool(toolName) ? .askUser : .tool,
                    icon: descriptor.iconKey,
                    verb: descriptor.verb,
                    chip: descriptor.chip,
                    status: .running,
                    toolName: toolName,
                    chipIsMonospaced: descriptor.chipIsMonospaced,
                    argsDetail: formatArgsDetail(toolName: toolName, argsSummary: argsSummary)
                )
                toolIndexByCallID[callID] = rows.count
                rows.append(row)

            case let .toolProgress(callID, label, _):
                if let index = toolIndexByCallID[callID] {
                    rows[index].chip = label
                }

            case let .toolResult(callID, payload):
                if let index = toolIndexByCallID[callID] {
                    var row = rows[index]
                    row.status = .completed
                    let summary = payload.summary ?? payload.title
                    row.resultDetail = summary
                    row.resultIsMarkdown = looksLikeMarkdown(summary)
                    if row.chip == nil || row.chip?.isEmpty == true {
                        row.chip = payload.title
                    }
                    rows[index] = row
                }

            case .askUser(_, let toolCallID):
                flushThinking()
                if let index = toolIndexByCallID[toolCallID] {
                    var row = rows[index]
                    row.kind = .askUser
                    row.status = .running
                    row.verb = "向你提问"
                    row.toolName = "ask_user"
                    rows[index] = row
                } else if let existingIndex = rows.lastIndex(where: { row in
                    row.kind == .askUser
                        || (row.status == .running && DeepTutorAskUserNormalizer.isAskUserTool(row.toolName))
                }) {
                    toolIndexByCallID[toolCallID] = existingIndex
                    var row = rows[existingIndex]
                    row.id = toolCallID
                    row.kind = .askUser
                    row.status = .running
                    row.verb = "向你提问"
                    row.toolName = "ask_user"
                    rows[existingIndex] = row
                    DeepTutorChatLog.traceRowDeduped(
                        toolCallID: toolCallID,
                        rowKind: "askUser",
                        reason: "reuse_running_ask_user_row"
                    )
                } else {
                    let row = DeepTutorTraceRowModel(
                        id: toolCallID,
                        kind: .askUser,
                        icon: DeepTutorTraceGlyph.speech.rawValue,
                        verb: "向你提问",
                        status: .running,
                        toolName: "ask_user"
                    )
                    toolIndexByCallID[toolCallID] = rows.count
                    rows.append(row)
                }

            case let .error(message, _):
                flushThinking()
                rows.append(
                    DeepTutorTraceRowModel(
                        id: "error-\(message.hashValue)",
                        kind: .error,
                        icon: DeepTutorTraceGlyph.error.rawValue,
                        verb: "失败",
                        chip: clipLabel(message, max: 56),
                        status: .failed,
                        resultDetail: message
                    )
                )

            default:
                continue
            }
        }

        flushThinking()
        return rows
    }

    static func formatDuration(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        if minutes > 0 {
            return "· \(minutes)m \(secs)s"
        }
        return "· \(secs)s"
    }

    // MARK: - Private

    private struct ToolDescriptor {
        let iconKey: String
        let verb: String
        let chip: String?
        let chipIsMonospaced: Bool
    }

    private static func describeTool(toolName: String, argsSummary: String?) -> ToolDescriptor {
        let normalized = toolName.lowercased()
        let args = parseArgs(argsSummary)

        switch normalized {
        case "ask_user", SparkToolName.askUserQuestion.rawValue:
            return ToolDescriptor(iconKey: DeepTutorTraceGlyph.speech.rawValue, verb: "向你提问", chip: nil, chipIsMonospaced: false)
        case "web_search", "search":
            return ToolDescriptor(
                iconKey: DeepTutorTraceGlyph.globe.rawValue,
                verb: "联网搜索",
                chip: clipLabel(args["query"] ?? argsSummary),
                chipIsMonospaced: false
            )
        case "web_fetch", "fetch":
            return ToolDescriptor(
                iconKey: DeepTutorTraceGlyph.globe.rawValue,
                verb: "抓取网页",
                chip: hostLabel(args["url"] ?? argsSummary),
                chipIsMonospaced: true
            )
        case "rag":
            return ToolDescriptor(
                iconKey: DeepTutorTraceGlyph.knowledge.rawValue,
                verb: "检索知识库",
                chip: clipLabel(args["query"] ?? argsSummary),
                chipIsMonospaced: false
            )
        case "read_file", "read_source", "read_skill":
            return ToolDescriptor(
                iconKey: DeepTutorTraceGlyph.knowledge.rawValue,
                verb: normalized == "read_skill" ? "读取技能" : "读取文件",
                chip: clipLabel(basename(args["path"] ?? args["name"] ?? args["source_id"] ?? argsSummary), max: 48),
                chipIsMonospaced: true
            )
        case "exec", "code_execution":
            return ToolDescriptor(
                iconKey: DeepTutorTraceGlyph.command.rawValue,
                verb: normalized == "code_execution" ? "运行代码" : "运行命令",
                chip: clipLabel(args["command"] ?? args["language"] ?? argsSummary, max: 48),
                chipIsMonospaced: true
            )
        case "paper_search":
            return ToolDescriptor(
                iconKey: DeepTutorTraceGlyph.globe.rawValue,
                verb: "搜索论文",
                chip: clipLabel(args["query"] ?? argsSummary),
                chipIsMonospaced: false
            )
        default:
            return ToolDescriptor(
                iconKey: DeepTutorTraceGlyph.tool.rawValue,
                verb: humanizedToolName(toolName),
                chip: clipLabel(argsSummary),
                chipIsMonospaced: false
            )
        }
    }

    private static func formatArgsDetail(toolName: String, argsSummary: String?) -> String? {
        guard let argsSummary, argsSummary.isEmpty == false else { return nil }
        if let data = argsSummary.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: pretty, encoding: .utf8) {
            return string
        }
        if argsSummary.contains("{") || argsSummary.contains("=") {
            return argsSummary
        }
        return "{\n  \"query\": \"\(argsSummary)\"\n}"
    }

    private static func parseArgs(_ raw: String?) -> [String: String] {
        guard let raw, raw.isEmpty == false else { return [:] }
        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var result: [String: String] = [:]
            for (key, value) in object {
                if let string = value as? String {
                    result[key] = string
                } else if let encoded = try? JSONSerialization.data(withJSONObject: value),
                          let json = String(data: encoded, encoding: .utf8) {
                    result[key] = json
                } else {
                    result[key] = String(describing: value)
                }
            }
            return result
        }
        return ["query": raw]
    }

    private static func clipLabel(_ text: String?, max: Int = 56) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return nil }
        if value.count <= max { return value }
        let cut = String(value.prefix(max))
        if let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > Int(Double(max) * 0.6) {
            return String(cut[..<lastSpace]) + "…"
        }
        return cut + "…"
    }

    private static func hostLabel(_ raw: String?) -> String? {
        guard let raw, raw.isEmpty == false else { return nil }
        if let url = URL(string: raw), let host = url.host {
            return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        }
        return clipLabel(raw, max: 48)
    }

    private static func basename(_ path: String?) -> String? {
        guard let path, path.isEmpty == false else { return nil }
        return (path as NSString).lastPathComponent
    }

    private static func humanizedToolName(_ toolName: String) -> String {
        toolName
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeMarkdown(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.contains("\n") || text.contains("**") || text.contains("#") || text.contains("🔗")
    }

    private static func estimatedDuration(from events: [DeepTutorStreamEvent]) -> Double? {
        guard events.isEmpty == false else { return nil }
        return max(1, Double(events.count) * 0.4)
    }
}
