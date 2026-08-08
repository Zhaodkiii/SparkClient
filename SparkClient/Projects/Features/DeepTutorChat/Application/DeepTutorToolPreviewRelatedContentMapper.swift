import Foundation

enum DeepTutorToolPreviewRelatedContentMapper {
    static func makePrompt(
        message: DeepTutorMessage,
        row: DeepTutorTraceRowModel
    ) -> DeepTutorToolPreviewPrompt {
        let toolCallID = normalizedToolCallID(for: row)
        return DeepTutorToolPreviewPrompt(
            conversationID: message.conversationID,
            messageID: message.id,
            toolCallID: toolCallID,
            toolName: row.toolName ?? row.verb,
            displayTitle: row.verb,
            arguments: row.argsDetail,
            output: row.resultDetail,
            outputIsMarkdown: row.resultIsMarkdown,
            metadata: metadata(for: row),
            relatedContent: relatedContent(message: message, toolCallID: toolCallID, row: row)
        )
    }

    private static func normalizedToolCallID(for row: DeepTutorTraceRowModel) -> String? {
        let trimmed = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func metadata(for row: DeepTutorTraceRowModel) -> [String: String] {
        var values: [String: String] = [
            "status": row.status.rawValue,
        ]
        if let chip = row.chip, chip.isEmpty == false {
            values["label"] = chip
        }
        if let durationSeconds = row.durationSeconds {
            values["duration"] = DeepTutorTraceFormatter.formatDuration(durationSeconds) ?? String(format: "%.2fs", durationSeconds)
        }
        return values
    }

    private static func relatedContent(
        message: DeepTutorMessage,
        toolCallID: String?,
        row: DeepTutorTraceRowModel
    ) -> [DeepTutorToolPreviewRelatedContent] {
        var items: [DeepTutorToolPreviewRelatedContent] = []

        if let toolCallID {
            for block in message.blocks where resolvedToolCallID(for: block) == toolCallID {
                if let item = item(for: block) {
                    items.append(item)
                }
            }
        }

        if items.isEmpty {
            for block in message.blocks {
                guard isToolRelatedBlock(block) else { continue }
                if let item = item(for: block) {
                    items.append(item)
                }
            }
        }

        if items.isEmpty, shouldCreateFallbackMessageCard(for: row) {
            items.append(
                DeepTutorToolPreviewRelatedContent(
                    id: "fallback|\(toolCallID ?? row.id)",
                    kindLabel: "消息卡片",
                    title: row.verb,
                    subtitle: nil,
                    body: row.resultDetail ?? row.argsDetail,
                    badges: [],
                    actions: []
                )
            )
        }

        return items
    }

    private static func resolvedToolCallID(for block: DeepTutorMessageBlock) -> String? {
        if let value = block.toolCallID?.trimmingCharacters(in: .whitespacesAndNewlines),
           value.isEmpty == false {
            return value
        }

        switch block.payload {
        case .askUser(let payload):
            let value = payload.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        case .memberSelection(let payload):
            let value = payload.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        case .captureCard(let payload):
            let value = payload.sourceToolCallID?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        case .memberProfile(let payload):
            let value = payload.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        default:
            return nil
        }
    }

    private static func isToolRelatedBlock(_ block: DeepTutorMessageBlock) -> Bool {
        switch block.payload {
        case .askUser, .captureCard, .memberSelection, .memberProfile, .generatedFile, .researchOutline, .quiz:
            return true
        default:
            return false
        }
    }

    private static func item(for block: DeepTutorMessageBlock) -> DeepTutorToolPreviewRelatedContent? {
        switch block.payload {
        case .askUser(let payload):
            let summary = payload.payload.questions.prefix(2).map(\.prompt).joined(separator: "\n")
            return DeepTutorToolPreviewRelatedContent(
                id: "askUser|\(block.id.uuidString)",
                kindLabel: "提问卡片",
                title: payload.payload.intro ?? "向你提问",
                subtitle: payload.isResolved ? "已回答" : "等待回答",
                body: summary.isEmpty ? nil : summary,
                badges: payload.answers.isEmpty ? [] : payload.answers.map(\.text).prefix(2).map { $0 },
                actions: []
            )
        case .memberSelection(let payload):
            let selection = payload.selectedMemberName ?? payload.selectedMemberID.map { "成员 #\($0)" }
            return DeepTutorToolPreviewRelatedContent(
                id: "member|\(block.id.uuidString)",
                kindLabel: "成员选择",
                title: "选择成员",
                subtitle: selection,
                body: payload.reason,
                badges: [payload.status.rawValue],
                actions: []
            )
        case .captureCard(let payload):
            return DeepTutorToolPreviewRelatedContent(
                id: "capture|\(block.id.uuidString)",
                kindLabel: "附件卡片",
                title: payload.title,
                subtitle: payload.cardType.rawValue,
                body: payload.subtitle,
                badges: payload.cardType.supportsFiles ? ["拍照", "相册", "文件"] : ["拍照", "相册"],
                actions: []
            )
        case .memberProfile(let payload):
            return DeepTutorToolPreviewRelatedContent(
                id: "memberProfile|\(block.id.uuidString)",
                kindLabel: "成员资料",
                title: "已获取 \(payload.memberName) 的医疗资料",
                subtitle: "\(payload.relationshipText) · \(payload.genderText) · \(payload.ageText)",
                body: payload.riskAssessmentSummary,
                badges: ["体检\(payload.healthExamReportCount)", "用药\(payload.medicationPlanCount)"],
                actions: []
            )
        case .generatedFile(let payload):
            return DeepTutorToolPreviewRelatedContent(
                id: "file|\(block.id.uuidString)",
                kindLabel: "生成文件",
                title: payload.filename,
                subtitle: payload.mimeType,
                body: payload.previewURL ?? payload.localPath,
                badges: payload.generated ? ["已生成"] : [],
                actions: []
            )
        case .researchOutline(let payload):
            let sectionTitles = payload.sections.prefix(3).map(\.title).joined(separator: " · ")
            return DeepTutorToolPreviewRelatedContent(
                id: "outline|\(block.id.uuidString)",
                kindLabel: "研究提纲",
                title: payload.title,
                subtitle: payload.sections.isEmpty ? nil : "\(payload.sections.count) 个章节",
                body: sectionTitles.isEmpty ? nil : sectionTitles,
                badges: [],
                actions: []
            )
        case .quiz(let payload):
            return DeepTutorToolPreviewRelatedContent(
                id: "quiz|\(block.id.uuidString)",
                kindLabel: "问答卡片",
                title: payload.title,
                subtitle: payload.questions.isEmpty ? nil : "\(payload.questions.count) 道题",
                body: payload.questions.first?.question,
                badges: payload.questions.first?.options.prefix(2).map(\.text) ?? [],
                actions: []
            )
        default:
            return nil
        }
    }

    private static func shouldCreateFallbackMessageCard(for row: DeepTutorTraceRowModel) -> Bool {
        let raw = (row.toolName ?? row.verb).lowercased()
        return raw.contains("card") || row.verb.contains("卡片")
    }
}
