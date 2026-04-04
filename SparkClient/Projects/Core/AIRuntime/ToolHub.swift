import Foundation

final class ToolHub: @unchecked Sendable {
    private let extractDraftUseCase: ExtractMedicalDraftFromDocumentUseCase
    private let confirmDraftUseCase: ConfirmMedicalDraftUseCase
    private let loadLatestDraftUseCase: LoadLatestMedicalDraftUseCase
    private let auditStore: ToolAuditStore
    private let logger: Logger

    init(
        extractDraftUseCase: ExtractMedicalDraftFromDocumentUseCase,
        confirmDraftUseCase: ConfirmMedicalDraftUseCase,
        loadLatestDraftUseCase: LoadLatestMedicalDraftUseCase,
        auditStore: ToolAuditStore,
        logger: Logger = ConsoleLogger()
    ) {
        self.extractDraftUseCase = extractDraftUseCase
        self.confirmDraftUseCase = confirmDraftUseCase
        self.loadLatestDraftUseCase = loadLatestDraftUseCase
        self.auditStore = auditStore
        self.logger = logger
    }

    func runIfNeeded(userInput: String, patientID: UUID?) async -> ToolHubResult {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return .none }
        logger.debug("ToolHub evaluating input: \(trimmed.prefix(24))", category: "tool_hub")

        if trimmed.hasPrefix("/ocr ") {
            guard let patientID else {
                return .executed(
                    ToolExecutionResult(
                        toolName: "ocr_extract_draft",
                        outputText: "当前未选择成员，无法生成病历草稿。",
                        sensitive: false,
                        shouldBypassModel: true
                    )
                )
            }

            let path = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let draft = try await extractDraftUseCase.execute(patientID: patientID, filePath: path)
                let output = """
                已生成病历草稿：
                标题：\(draft.title)
                摘要：\(draft.summary)
                诊断：\(draft.diagnosis ?? "待补充")

                如需写入正式病历，请发送 /confirm_draft
                """
                await auditStore.append(
                    ToolAuditEvent(
                        toolName: "ocr_extract_draft",
                        patientID: patientID,
                        inputSummary: path,
                        outputSummary: String(output.prefix(120)),
                        status: .success
                    )
                )
                return .executed(
                    ToolExecutionResult(
                        toolName: "ocr_extract_draft",
                        outputText: output,
                        sensitive: true,
                        shouldBypassModel: true
                    )
                )
            } catch {
                let message = "病历草稿抽取失败：\(error.localizedDescription)"
                await auditStore.append(
                    ToolAuditEvent(
                        toolName: "ocr_extract_draft",
                        patientID: patientID,
                        inputSummary: path,
                        outputSummary: message,
                        status: .failed
                    )
                )
                return .executed(
                    ToolExecutionResult(
                        toolName: "ocr_extract_draft",
                        outputText: message,
                        sensitive: false,
                        shouldBypassModel: true
                    )
                )
            }
        }

        if trimmed == "/confirm_draft" {
            guard let patientID else {
                return .executed(
                    ToolExecutionResult(
                        toolName: "confirm_draft",
                        outputText: "当前未选择成员，无法确认草稿。",
                        sensitive: false,
                        shouldBypassModel: true
                    )
                )
            }

            guard let latestDraft = await loadLatestDraftUseCase.execute(patientID: patientID) else {
                return .executed(
                    ToolExecutionResult(
                        toolName: "confirm_draft",
                        outputText: "未找到可确认的草稿，请先发送 /ocr <文件路径>。",
                        sensitive: false,
                        shouldBypassModel: true
                    )
                )
            }

            do {
                let record = try await confirmDraftUseCase.execute(patientID: patientID)
                let output = "草稿确认成功，已写入病历：\(record.title)（\(record.occurredAt.formatted(date: .abbreviated, time: .omitted))）"
                await auditStore.append(
                    ToolAuditEvent(
                        toolName: "confirm_draft",
                        patientID: patientID,
                        inputSummary: latestDraft.title,
                        outputSummary: output,
                        status: .success
                    )
                )
                return .executed(
                    ToolExecutionResult(
                        toolName: "confirm_draft",
                        outputText: output,
                        sensitive: true,
                        shouldBypassModel: true
                    )
                )
            } catch {
                let output = "草稿确认失败：\(error.localizedDescription)"
                await auditStore.append(
                    ToolAuditEvent(
                        toolName: "confirm_draft",
                        patientID: patientID,
                        inputSummary: latestDraft.title,
                        outputSummary: output,
                        status: .failed
                    )
                )
                return .executed(
                    ToolExecutionResult(
                        toolName: "confirm_draft",
                        outputText: output,
                        sensitive: false,
                        shouldBypassModel: true
                    )
                )
            }
        }

        if trimmed == "/audit_tools" {
            let events = await auditStore.recent(limit: 10)
            if events.isEmpty {
                return .executed(
                    ToolExecutionResult(
                        toolName: "audit_tools",
                        outputText: "最近没有工具调用审计记录。",
                        sensitive: false,
                        shouldBypassModel: true
                    )
                )
            }
            let lines = events.map { event in
                "[\(event.createdAt.formatted(date: .abbreviated, time: .shortened))] \(event.toolName) - \(event.status.rawValue)"
            }
            return .executed(
                ToolExecutionResult(
                    toolName: "audit_tools",
                    outputText: lines.joined(separator: "\n"),
                    sensitive: false,
                    shouldBypassModel: true
                )
            )
        }

        return .none
    }
}
