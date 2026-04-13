import Foundation

/// 工具事件解释器：
/// - 输入：编排层输出（toolName/toolContent/kind/text）；
/// - 输出：可直接持久化到消息附件的结构化字段；
/// - 目标：把“工具结果解析 + UI 卡片生成”从 UseCase 主流程中解耦，降低发送链路复杂度。
struct ChatToolEventInterpreter: Sendable {
    let logger: Logger
    let runtimeAttachmentBuilder: ChatToolRuntimeAttachmentBuilder

    init(
        logger: Logger = ConsoleLogger(),
        runtimeAttachmentBuilder: ChatToolRuntimeAttachmentBuilder = ChatToolRuntimeAttachmentBuilder()
    ) {
        self.logger = logger
        self.runtimeAttachmentBuilder = runtimeAttachmentBuilder
    }

    /// 解释一次助手输出，生成标准附件集合。
    /// 注意：这里仅生成“消息内预览数据”，不做最终知识库落库。
    func interpret(
        kind: ChatMessageKind,
        text: String,
        toolName: String?,
        toolContent: String?
    ) -> ChatToolInterpretationResult {
        let toolAttachments = makeToolAttachments(toolName: toolName, toolContent: toolContent)
        let knowledgeCardAttachments = makeKnowledgeCardAttachments(
            kind: kind,
            text: text,
            toolName: toolName,
            toolContent: toolContent
        )
        let richAttachments = makeRichUIAttachments(toolName: toolName, toolContent: toolContent)

        let result = ChatToolInterpretationResult(
            attachments: toolAttachments + knowledgeCardAttachments + richAttachments,
            toolAttachmentCount: toolAttachments.count,
            knowledgeCardAttachmentCount: knowledgeCardAttachments.count,
            richAttachmentCount: richAttachments.count
        )
        logger.debug(
            "工具事件解释完成 tool=\(toolName ?? "-") toolAttach=\(result.toolAttachmentCount) knowledgeAttach=\(result.knowledgeCardAttachmentCount) richAttach=\(result.richAttachmentCount)",
            module: .general
        )
        return result
    }

    private func makeToolAttachments(
        toolName: String?,
        toolContent: String?
    ) -> [ChatAttachment] {
        runtimeAttachmentBuilder.build(toolName: toolName, toolContent: toolContent)
    }

    private func makeKnowledgeCardAttachments(
        kind: ChatMessageKind,
        text: String,
        toolName: String?,
        toolContent: String?
    ) -> [ChatAttachment] {
        // 先生成“可预览知识卡”到消息附件，后续由用户在卡片内点击保存。
        var cards: [KnowledgeCardPayload] = []
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolNameLower = (toolName ?? "").lowercased()

        // 规则 1：命中知识检索工具时，优先用工具结果生成知识检索卡。
        if toolNameLower.contains("search_knowledge_bag") {
            let body = (toolContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty == false {
                cards.append(KnowledgeCardPayload(title: "知识检索", content: body))
            }
        // 规则 2：模型显式调用 create_knowledge_document 时，按工具返回草稿生成知识卡预览。
        } else if toolNameLower.contains("create_knowledge_document") {
            if let draft = parseKnowledgeDraft(from: toolContent) {
                cards.append(KnowledgeCardPayload(title: draft.title, content: draft.content))
            }
        // 规则 3：当回复类型本身是 card，使用模型回复正文生成知识卡。
        } else if kind == .card, trimmedText.isEmpty == false {
            cards.append(KnowledgeCardPayload(title: "知识卡片", content: trimmedText))
        }

        // 无卡片内容则不附带 knowledge_card，避免空卡片渲染。
        guard cards.isEmpty == false,
              let data = try? JSONEncoder().encode(cards),
              let json = String(data: data, encoding: .utf8)
        else {
            return []
        }
        return [ChatAttachment(type: ChatStreamFieldKey.knowledgeCard, text: json)]
    }

    /// 解析 create_knowledge_document 工具输出，兼容 JSON 与 key=value 两种格式。
    private func parseKnowledgeDraft(from toolContent: String?) -> (title: String, content: String)? {
        let raw = (toolContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else { return nil }

        // 情况 1：工具 trace 里包裹了 JSON（例如 "[1] create_knowledge_document\n{...}"）。
        // 先抽取最外层 JSON 对象，避免前缀文本导致反序列化失败。
        let jsonCandidate: String
        if let start = raw.firstIndex(of: "{"),
           let end = raw.lastIndex(of: "}"),
           start <= end {
            jsonCandidate = String(raw[start ... end])
        } else {
            jsonCandidate = raw
        }

        if let data = jsonCandidate.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let title = (object["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let content = (object["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard content.isEmpty == false else { return nil }
            return (title.isEmpty ? "知识文档草稿" : title, content)
        }

        // 情况 2：回退兼容 key=value 行格式。
        var title = ""
        var content = ""
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("title=") {
                title = String(trimmed.dropFirst("title=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("content=") {
                content = String(trimmed.dropFirst("content=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard content.isEmpty == false else { return nil }
        return (title.isEmpty ? "知识文档草稿" : title, content)
    }

    private func makeRichUIAttachments(
        toolName: String?,
        toolContent: String?
    ) -> [ChatAttachment] {
        let name = (toolName ?? "").lowercased()
        let content = (toolContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else { return [] }
        var attachments: [ChatAttachment] = []
        let args = parseArgsFromToolContent(content)

        if name.contains("query_location") || name.contains("get_current_location") || name.contains("search_nearby_locations") || name.contains("get_route") {
            if let latitude = Double(args["latitude"] ?? ""),
               let longitude = Double(args["longitude"] ?? "") {
                let loc = [RichLocation(name: args["keyword"] ?? args["query"] ?? "Location", latitude: latitude, longitude: longitude)]
                if let text = jsonString(loc) {
                    attachments.append(ChatAttachment(type: ChatStreamFieldKey.locationsInfo, text: text))
                }
            }
            if let startLat = Double(args["start.latitude"] ?? ""),
               let startLng = Double(args["start.longitude"] ?? ""),
               let endLat = Double(args["end.latitude"] ?? ""),
               let endLng = Double(args["end.longitude"] ?? "") {
                let loc = [
                    RichLocation(name: "Start", latitude: startLat, longitude: startLng),
                    RichLocation(name: "End", latitude: endLat, longitude: endLng),
                ]
                if let text = jsonString(loc) {
                    attachments.append(ChatAttachment(type: ChatStreamFieldKey.locationsInfo, text: text))
                }
                let routes = [RichRoute(summary: "Route", distance: args["distance"], duration: args["duration"], mode: args["mode"])]
                if let text = jsonString(routes) {
                    attachments.append(ChatAttachment(type: ChatStreamFieldKey.routeInfo, text: text))
                }
            }
        }

        if name.contains("search_calendar_and_reminders") || name.contains("write_system_event") {
            let events = [RichEvent(
                type: args["event_type"] ?? args["type"] ?? "calendar",
                title: args["title"] ?? args["keyword"] ?? "Event",
                dateText: args["start_date"] ?? args["due_date"] ?? args["end_date"],
                location: args["location"],
                notes: args["notes"]
            )]
            if let text = jsonString(events) {
                attachments.append(ChatAttachment(type: ChatStreamFieldKey.events, text: text))
            }
        }

        if name.contains("generate_structured_health_card") {
            let card = [RichHealthCard(
                title: args["category"] ?? "Health Card",
                energyKilocalories: Double(args["energy"] ?? ""),
                proteinGrams: Double(args["protein"] ?? ""),
                carbohydratesGrams: Double(args["carbohydrates"] ?? ""),
                fatGrams: Double(args["fat"] ?? ""),
                dateText: nil
            )]
            if let text = jsonString(card) {
                attachments.append(ChatAttachment(type: ChatStreamFieldKey.healthInfo, text: text))
            }
        }

        if name.contains("fetch_sleep_details"),
           let sleepModel = parseSleepModel(from: content),
           let text = jsonString(sleepModel) {
            attachments.append(ChatAttachment(type: ChatStreamFieldKey.healthSleepVisualization, text: text))
        }

        // 网页内容字段（如工具直接返回 HTML），对齐 StreamData.htmlContent。
        if name.contains("read_web_page") || name.contains("create_webpage") {
            attachments.append(ChatAttachment(type: ChatStreamFieldKey.htmlContent, text: content))
        }

        return attachments
    }

    private func parseArgsFromToolContent(_ content: String) -> [String: String] {
        guard let argsLine = content
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("args=") })
        else { return [:] }
        let raw = String(argsLine.dropFirst(5))
        let pairs = raw.split(separator: ",")
        var result: [String: String] = [:]
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = value
        }
        return result
    }

    private func jsonString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func parseSleepModel(from toolContent: String) -> ChatHealthSleepModel? {
        if let prefixed = toolContent
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("sleep_model=") }) {
            let raw = String(prefixed.dropFirst("sleep_model=".count))
            if let data = raw.data(using: .utf8),
               let model = try? JSONDecoder().decode(ChatHealthSleepModel.self, from: data) {
                return model
            }
        }

        if let start = toolContent.firstIndex(of: "{"),
           let end = toolContent.lastIndex(of: "}"),
           start <= end {
            let json = String(toolContent[start ... end])
            if let data = json.data(using: .utf8),
               let wrapper = try? JSONDecoder().decode(SleepModelWrapper.self, from: data) {
                return wrapper.sleepModel
            }
        }
        return nil
    }
}

struct ChatToolInterpretationResult: Sendable {
    let attachments: [ChatAttachment]
    let toolAttachmentCount: Int
    let knowledgeCardAttachmentCount: Int
    let richAttachmentCount: Int
}

private struct KnowledgeCardPayload: Codable, Sendable {
    let title: String
    let content: String
}

private struct RichLocation: Codable, Sendable {
    let id: UUID = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
}

private struct RichRoute: Codable, Sendable {
    let id: UUID = UUID()
    let summary: String
    let distance: String?
    let duration: String?
    let mode: String?
}

private struct RichEvent: Codable, Sendable {
    let id: UUID = UUID()
    let type: String
    let title: String
    let dateText: String?
    let location: String?
    let notes: String?
}

private struct RichHealthCard: Codable, Sendable {
    let id: UUID = UUID()
    let title: String
    let energyKilocalories: Double?
    let proteinGrams: Double?
    let carbohydratesGrams: Double?
    let fatGrams: Double?
    let dateText: String?
}

private struct SleepModelWrapper: Codable, Sendable {
    let sleepModel: ChatHealthSleepModel

    enum CodingKeys: String, CodingKey {
        case sleepModel = "sleep_model"
    }
}
