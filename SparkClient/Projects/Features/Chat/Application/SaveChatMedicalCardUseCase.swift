import Foundation

struct SaveChatMedicalCardUseCase: Sendable {
    let submissionService: MedicalRecordFormSubmissionService
    let updateChatMessageAttachmentsUseCase: UpdateChatMessageAttachmentsUseCase
    let syncChatUseCase: SyncChatUseCase
    let logger: Logger

    func saveMedicationCard(
        memberID: Int,
        message: ChatMessage,
        card: ChatMedicationCardPayload
    ) async throws -> [ChatAttachment] {
        let draft = MedicationRecognitionDraft(
            genericName: card.name,
            brandName: nil,
            drugName: card.name,
            dosageForm: nil,
            strength: nil,
            route: nil,
            dosePerTime: card.dosage,
            doseValue: nil,
            doseUnit: nil,
            frequencyCode: nil,
            period: nil,
            timesPerPeriod: nil,
            frequencyText: card.frequency,
            durationDays: nil,
            instructions: card.instructions,
            reminderEnabled: nil,
            reminderTimes: nil,
            sortOrder: nil,
            extra: nil
        )
        let recordID = try await submissionService.submitMedicationSingle(memberID: memberID, draft: draft)
        return try await markCardSaved(
            message: message,
            attachmentType: ChatStreamFieldKey.medicationCards,
            cardID: card.id,
            recordID: recordID,
            patch: { row in
                ChatMedicationCardPayload(
                    id: row.id,
                    name: row.name,
                    dosage: row.dosage,
                    frequency: row.frequency,
                    instructions: row.instructions,
                    isSaved: true,
                    savedRecordID: recordID,
                    ossFileID: row.ossFileID
                )
            }
        )
    }

    func savePrescriptionCard(
        memberID: Int,
        message: ChatMessage,
        card: ChatPrescriptionCardPayload
    ) async throws -> [ChatAttachment] {
        let rows = card.medications.map { med in
            MedicationRecognitionDraft(
                genericName: med.name,
                brandName: nil,
                drugName: med.name,
                dosageForm: nil,
                strength: nil,
                route: nil,
                dosePerTime: med.dosage,
                doseValue: nil,
                doseUnit: nil,
                frequencyCode: nil,
                period: nil,
                timesPerPeriod: nil,
                frequencyText: med.frequency,
                durationDays: nil,
                instructions: med.instructions,
                reminderEnabled: nil,
                reminderTimes: nil,
                sortOrder: nil,
                extra: nil
            )
        }
        let draft = PrescriptionRecognitionDraft(
            medicalCase: nil,
            prescriberName: nil,
            institutionName: card.institutionName,
            prescribedAt: card.prescribedAt,
            diagnosis: card.diagnosis,
            batchNo: card.batchNo,
            status: nil,
            auditorName: nil,
            auditedAt: nil,
            extra: nil,
            medications: rows
        )
        let recordID = try await submissionService.submitPrescriptionBatch(memberID: memberID, draft: draft)
        return try await markCardSaved(
            message: message,
            attachmentType: ChatStreamFieldKey.prescriptionCards,
            cardID: card.id,
            recordID: recordID,
            patch: { row in
                ChatPrescriptionCardPayload(
                    id: row.id,
                    batchNo: row.batchNo,
                    institutionName: row.institutionName,
                    prescribedAt: row.prescribedAt,
                    diagnosis: row.diagnosis,
                    medications: row.medications,
                    isSaved: true,
                    savedRecordID: recordID,
                    ossFileID: row.ossFileID
                )
            }
        )
    }

    func saveExamReportCard(
        memberID: Int,
        message: ChatMessage,
        card: ChatExamReportCardPayload
    ) async throws -> [ChatAttachment] {
        let draft = MedicalReportRecognitionDraft(
            category: "medical_report",
            title: card.title,
            hospital: card.hospital,
            doctor: nil,
            content: card.conclusion ?? "",
            date: card.date,
            details: []
        )
        let recordID = try await submissionService.submitMedicalReportCreate(memberID: memberID, draft: draft)
        return try await markCardSaved(
            message: message,
            attachmentType: ChatStreamFieldKey.examReportCards,
            cardID: card.id,
            recordID: recordID,
            patch: { row in
                ChatExamReportCardPayload(
                    id: row.id,
                    title: row.title,
                    hospital: row.hospital,
                    date: row.date,
                    conclusion: row.conclusion,
                    isSaved: true,
                    savedRecordID: recordID,
                    ossFileID: row.ossFileID
                )
            }
        )
    }

    func saveMedicalCaseCard(
        memberID: Int,
        message: ChatMessage,
        card: ChatMedicalCaseCardPayload
    ) async throws -> [ChatAttachment] {
        let recordID = try await submissionService.workflowAPI.saveCase(
            .init(
                member: memberID,
                recordType: "outpatient",
                status: 1,
                title: card.title,
                hospitalName: card.hospitalName,
                ageAtVisit: nil,
                diagnosisSummary: [card.summary, card.diagnosis]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: "\n\n"),
                extra: card.occurredAt.map { ["occurred_at": $0, "source": "chat_card_save"] } ?? ["source": "chat_card_save"]
            )
        )
        return try await markCardSaved(
            message: message,
            attachmentType: ChatStreamFieldKey.medicalCaseCards,
            cardID: card.id,
            recordID: recordID,
            patch: { row in
                ChatMedicalCaseCardPayload(
                    id: row.id,
                    title: row.title,
                    summary: row.summary,
                    diagnosis: row.diagnosis,
                    hospitalName: row.hospitalName,
                    occurredAt: row.occurredAt,
                    isSaved: true,
                    savedRecordID: recordID,
                    ossFileID: row.ossFileID
                )
            }
        )
    }

    private func markCardSaved<T: Codable & Identifiable>(
        message: ChatMessage,
        attachmentType: String,
        cardID: T.ID,
        recordID: Int,
        patch: (T) -> T
    ) async throws -> [ChatAttachment] where T.ID: Equatable {
        guard let index = message.attachments.firstIndex(where: { $0.type == attachmentType }),
              let raw = message.attachments[index].text,
              let data = raw.data(using: .utf8) else {
            throw NSError(domain: "SaveChatMedicalCardUseCase", code: -1)
        }
        var rows = try JSONDecoder().decode([T].self, from: data)
        guard let rowIndex = rows.firstIndex(where: { $0.id == cardID }) else {
            throw NSError(domain: "SaveChatMedicalCardUseCase", code: -2)
        }
        rows[rowIndex] = patch(rows[rowIndex])
        let encoded = try JSONEncoder().encode(rows)
        guard let text = String(data: encoded, encoding: .utf8) else {
            throw NSError(domain: "SaveChatMedicalCardUseCase", code: -3)
        }
        var attachments = message.attachments
        attachments[index] = ChatAttachment(
            id: attachments[index].id,
            type: attachments[index].type,
            url: attachments[index].url,
            text: text
        )
        await updateChatMessageAttachmentsUseCase.execute(
            clientMessageID: message.clientMessageID,
            attachments: attachments,
            markPendingForSync: true
        )
        do {
            try await syncChatUseCase.pushOutboxOnly()
        } catch {
            logger.warning("医疗卡保存状态上送失败，recordID=\(recordID)，稍后重试", module: .general)
        }
        return attachments
    }
}
