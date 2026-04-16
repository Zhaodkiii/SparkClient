import Foundation

struct GenerateStructuredHealthCardsAsyncUseCase: Sendable {
    let repository: any ChatRepository
    let updateAttachmentsUseCase: UpdateChatMessageAttachmentsUseCase
    let syncChatUseCase: SyncChatUseCase
    let medicalStructuredExtractor: any MedicalDocumentStructuredExtracting
    let logger: Logger

    func kickoffIfNeeded(
        threadID: UUID,
        assistantClientMessageID: UUID,
        toolName: String?,
        toolContent: String?,
        onAttachmentsUpdated: (@Sendable ([ChatAttachment]) async -> Void)? = nil
    ) {
        guard (toolName ?? "").lowercased() == SparkToolName.generateStructuredHealthCard else { return }
        guard let descriptor = parseTaskDescriptor(from: toolContent) else { return }
        Task {
            await run(
                threadID: threadID,
                assistantClientMessageID: assistantClientMessageID,
                descriptor: descriptor,
                onAttachmentsUpdated: onAttachmentsUpdated
            )
        }
    }

    private func run(
        threadID: UUID,
        assistantClientMessageID: UUID,
        descriptor: AsyncStructuredTaskDescriptor,
        onAttachmentsUpdated: (@Sendable ([ChatAttachment]) async -> Void)?
    ) async {
        do {
            let output = try await medicalStructuredExtractor.extract(
                kind: descriptor.documentKind,
                mergedOCRText: descriptor.rawText
            )
            let payloadText = makeStructuredCardToolPayload(
                typedResult: output.typedResult,
                ossFileID: descriptor.ossFileID
            )
            guard let payloadData = payloadText.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(StructuredHealthToolPayload.self, from: payloadData) else {
                return
            }
            let currentMessages = await repository.loadMessages(threadID: threadID, limit: nil, before: nil)
            guard let target = currentMessages.last(where: { $0.clientMessageID == assistantClientMessageID }) else {
                return
            }
            let merged = mergeMedicalAttachments(base: target.attachments, payload: payload)
            await updateAttachmentsUseCase.execute(
                clientMessageID: assistantClientMessageID,
                attachments: merged,
                markPendingForSync: true
            )
            if let onAttachmentsUpdated {
                await onAttachmentsUpdated(merged)
            }
            do {
                try await syncChatUseCase.pushOutboxOnly()
            } catch {
                logger.warning("异步医疗卡片上送失败，稍后重试：\(error.localizedDescription)", module: .general)
            }
        } catch {
            logger.error("异步医疗卡片抽取失败：\(error.localizedDescription)", module: .medical)
        }
    }

    private func mergeMedicalAttachments(
        base: [ChatAttachment],
        payload: StructuredHealthToolPayload
    ) -> [ChatAttachment] {
        let medicalTypes: Set<String> = [
            ChatStreamFieldKey.medicationCards,
            ChatStreamFieldKey.prescriptionCards,
            ChatStreamFieldKey.examReportCards,
            ChatStreamFieldKey.medicalCaseCards
        ]
        var merged = base.filter { medicalTypes.contains($0.type) == false }
        if payload.medicationCards.isEmpty == false, let text = encode(payload.medicationCards) {
            merged.append(ChatAttachment(type: ChatStreamFieldKey.medicationCards, text: text))
        }
        if payload.prescriptionCards.isEmpty == false, let text = encode(payload.prescriptionCards) {
            merged.append(ChatAttachment(type: ChatStreamFieldKey.prescriptionCards, text: text))
        }
        if payload.examReportCards.isEmpty == false, let text = encode(payload.examReportCards) {
            merged.append(ChatAttachment(type: ChatStreamFieldKey.examReportCards, text: text))
        }
        if payload.medicalCaseCards.isEmpty == false, let text = encode(payload.medicalCaseCards) {
            merged.append(ChatAttachment(type: ChatStreamFieldKey.medicalCaseCards, text: text))
        }
        return merged
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func parseTaskDescriptor(from toolContent: String?) -> AsyncStructuredTaskDescriptor? {
        let text = (toolContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        for jsonText in jsonCandidates(in: text) {
            guard let data = jsonText.data(using: .utf8),
                  let descriptor = try? JSONDecoder().decode(AsyncStructuredTaskDescriptor.self, from: data),
                  descriptor.mode == "async_structured_extraction" else {
                continue
            }
            return descriptor
        }
        return nil
    }

    private func jsonCandidates(in text: String) -> [String] {
        let chars = Array(text)
        guard chars.isEmpty == false else { return [] }
        var results: [String] = []
        var stack: [Character] = []
        var start: Int?
        var inString = false
        var escaped = false
        for idx in chars.indices {
            let ch = chars[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }
            if ch == "\"" {
                inString = true
                continue
            }
            if ch == "{" || ch == "[" {
                if stack.isEmpty { start = idx }
                stack.append(ch)
                continue
            }
            if ch == "}" || ch == "]" {
                guard let last = stack.last else { continue }
                if (last == "{" && ch == "}") || (last == "[" && ch == "]") {
                    _ = stack.popLast()
                    if stack.isEmpty, let start, start <= idx {
                        results.append(String(chars[start...idx]))
                    }
                }
            }
        }
        return results
    }

    private func makeStructuredCardToolPayload(
        typedResult: MedicalDocumentTypedResult,
        ossFileID: Int?
    ) -> String {
        let ossFileValue: Any = ossFileID.map { $0 } ?? NSNull()
        let payload: [String: Any]
        switch typedResult {
        case .medication(let drafts):
            let medicationCards: [[String: Any]] = drafts.map { draft in
                [
                    "id": UUID().uuidString,
                    "name": draft.drugName ?? draft.genericName ?? draft.brandName ?? "未知药品",
                    "dosage": draft.dosePerTime ?? "",
                    "frequency": draft.frequencyText ?? draft.frequencyCode ?? "",
                    "instructions": draft.instructions ?? "",
                    "isSaved": false,
                    "savedRecordID": NSNull(),
                    "ossFileID": ossFileValue
                ]
            }
            payload = [
                "medication_cards": medicationCards
            ]
        case .prescription(let draft):
            let meds: [[String: Any]] = (draft.medications ?? []).map { med in
                [
                    "id": UUID().uuidString,
                    "name": med.drugName ?? med.genericName ?? med.brandName ?? "未知药品",
                    "dosage": med.dosePerTime ?? "",
                    "frequency": med.frequencyText ?? med.frequencyCode ?? "",
                    "instructions": med.instructions ?? "",
                    "isSaved": false,
                    "savedRecordID": NSNull(),
                    "ossFileID": ossFileValue
                ]
            }
            let prescriptionCard: [String: Any] = [
                "id": UUID().uuidString,
                "batchNo": draft.batchNo ?? "",
                "institutionName": draft.institutionName ?? "",
                "prescribedAt": draft.prescribedAt ?? "",
                "diagnosis": draft.diagnosis ?? "",
                "medications": meds,
                "isSaved": false,
                "savedRecordID": NSNull(),
                "ossFileID": ossFileValue
            ]
            payload = [
                "prescription_cards": [prescriptionCard]
            ]
        case .medicalReport(let drafts):
            let examCards: [[String: Any]] = drafts.map { draft in
                [
                    "id": UUID().uuidString,
                    "title": draft.title,
                    "hospital": draft.hospital ?? "",
                    "date": draft.date ?? "",
                    "conclusion": draft.content,
                    "isSaved": false,
                    "savedRecordID": NSNull(),
                    "ossFileID": ossFileValue
                ]
            }
            payload = [
                "exam_report_cards": examCards
            ]
        case .caseDocument(let draft):
            let caseCard: [String: Any] = [
                "id": UUID().uuidString,
                "title": draft.title,
                "summary": draft.summary ?? "",
                "diagnosis": draft.diagnosis ?? "",
                "hospitalName": draft.hospitalName ?? "",
                "occurredAt": draft.occurredAt ?? "",
                "isSaved": false,
                "savedRecordID": NSNull(),
                "ossFileID": ossFileValue
            ]
            payload = [
                "medical_case_cards": [caseCard]
            ]
        case .healthExamReport(let draft):
            let healthExamCard: [String: Any] = [
                "id": UUID().uuidString,
                "title": draft.examType ?? "体检报告",
                "hospital": draft.institutionName ?? "",
                "date": draft.examDate ?? "",
                "conclusion": draft.summary ?? "",
                "isSaved": false,
                "savedRecordID": NSNull(),
                "ossFileID": ossFileValue
            ]
            payload = [
                "exam_report_cards": [healthExamCard]
            ]
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

private struct AsyncStructuredTaskDescriptor: Decodable {
    let mode: String
    let reportType: String
    let rawText: String
    let documentKindRaw: String
    let ossFileID: Int?

    enum CodingKeys: String, CodingKey {
        case mode
        case reportType = "report_type"
        case rawText = "raw_text"
        case documentKindRaw = "document_kind"
        case ossFileID = "oss_file_id"
    }

    var documentKind: MedicalDocumentKind {
        switch documentKindRaw {
        case MedicalDocumentKind.medication.rawValue:
            return .medication
        case MedicalDocumentKind.prescription.rawValue:
            return .prescription
        case MedicalDocumentKind.medicalReport.rawValue:
            return .medicalReport
        case MedicalDocumentKind.caseDocument.rawValue:
            return .caseDocument
        case MedicalDocumentKind.healthExamReport.rawValue:
            return .healthExamReport
        default:
            switch reportType {
            case "medication":
                return .medication
            case "prescription":
                return .prescription
            case "exam_report":
                return .medicalReport
            default:
                return .caseDocument
            }
        }
    }
}

private struct StructuredHealthToolPayload: Codable, Sendable {
    let medicationCards: [ChatMedicationCardPayload]
    let prescriptionCards: [ChatPrescriptionCardPayload]
    let examReportCards: [ChatExamReportCardPayload]
    let medicalCaseCards: [ChatMedicalCaseCardPayload]

    enum CodingKeys: String, CodingKey {
        case medicationCards = "medication_cards"
        case prescriptionCards = "prescription_cards"
        case examReportCards = "exam_report_cards"
        case medicalCaseCards = "medical_case_cards"
    }
}
