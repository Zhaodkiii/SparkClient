import Foundation

struct DefaultMedicalDocumentTypeResolver: MedicalDocumentTypeResolving, Sendable {
    let runtimeService: any AIRuntimeServing
    let promptFactory: any MedicalPromptBuilding
    let logger: Logger

    init(
        runtimeService: any AIRuntimeServing,
        promptFactory: any MedicalPromptBuilding,
        logger: Logger = ConsoleLogger()
    ) {
        self.runtimeService = runtimeService
        self.promptFactory = promptFactory
        self.logger = logger
    }

    func resolve(
        selectedKind: MedicalDocumentKind,
        mergedOCRText: String
    ) async throws -> MedicalDocumentTypeResolution {
        if selectedKind != .auto {
            return MedicalDocumentTypeResolution(kind: selectedKind, confidence: 1, source: .manual, reason: "manual_selected")
        }

        if let rules = resolveByRules(text: mergedOCRText) {
            return rules
        }

        let prompt = promptFactory.typeRecognitionPrompt(ocrText: mergedOCRText)
        let responseText = try await collectResponseText(
            from: try await runtimeService.generateTextStream(
                request: AIRuntimeTextRequest(
                    scenario: .medicalDocumentTypeRecognition,
                    messages: [AIRuntimeMessage(role: .user, content: prompt)],
                    reasoning: .disabled
                )
            )
        )
        let parsed = parseAIResponse(responseText) ?? .init(kind: .medicalReport, confidence: 0.4, source: .ai, reason: "ai_fallback_default")
        logger.info("AI 类型识别完成，kind=\(parsed.kind.rawValue), confidence=\(parsed.confidence)", category: "medical_upload")
        return parsed
    }

    private func resolveByRules(text: String) -> MedicalDocumentTypeResolution? {
        let lower = text.lowercased()
        let scores: [(MedicalDocumentKind, Int)] = [
            (.prescription, score(text: lower, keywords: ["处方", "prescription", "rx", "医嘱"])),
            (.medication, score(text: lower, keywords: ["用药", "服药", "dosage", "frequency", "药品"])),
            (.healthExamReport, score(text: lower, keywords: ["体检", "health exam", "检验结论", "体检报告"])),
            (.medicalReport, score(text: lower, keywords: ["检查报告", "影像", "检验", "impression", "findings"])),
            (.caseDocument, score(text: lower, keywords: ["门诊病历", "住院记录", "病历", "主诉", "现病史"]))
        ]
        guard let best = scores.max(by: { $0.1 < $1.1 }), best.1 >= 2 else {
            return nil
        }
        return MedicalDocumentTypeResolution(
            kind: best.0,
            confidence: min(0.95, Double(best.1) / 8.0),
            source: .localRules,
            reason: "keyword_rules"
        )
    }

    private func score(text: String, keywords: [String]) -> Int {
        keywords.reduce(0) { partial, keyword in
            partial + (text.contains(keyword.lowercased()) ? 1 : 0)
        }
    }

    private func parseAIResponse(_ text: String) -> MedicalDocumentTypeResolution? {
        let payload = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8) else { return nil }
        struct Parsed: Decodable {
            let kind: String?
            let confidence: Double?
            let reason: String?
        }
        guard let parsed = try? JSONDecoder().decode(Parsed.self, from: data),
              let rawKind = parsed.kind else { return nil }
        let kind = mapKind(rawKind)
        return MedicalDocumentTypeResolution(
            kind: kind,
            confidence: parsed.confidence ?? 0.5,
            source: .ai,
            reason: parsed.reason
        )
    }

    private func mapKind(_ raw: String) -> MedicalDocumentKind {
        switch raw.lowercased() {
        case "case_document", "casedocument":
            return .caseDocument
        case "health_exam_report", "healthexamreport":
            return .healthExamReport
        case "prescription":
            return .prescription
        case "medication":
            return .medication
        default:
            return .medicalReport
        }
    }

    private func collectResponseText(
        from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>
    ) async throws -> String {
        var bufferedText = ""
        var completedText: String?
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                bufferedText.append(delta)
            case .completed(let response):
                completedText = response.text
            case .reasoningDelta, .toolCallDelta:
                continue
            }
        }
        return completedText ?? bufferedText
    }
}
