import Foundation

enum ConfirmMedicalDraftError: LocalizedError {
    case draftNotFound

    var errorDescription: String? {
        switch self {
        case .draftNotFound:
            return "未找到可确认的病历草稿。"
        }
    }
}

struct ConfirmMedicalDraftUseCase: Sendable {
    let draftRepository: any MedicalDraftRepository
    let medicalDataRepository: any MedicalDataRepository

    func execute(patientID: UUID) async throws -> MedicalRecord {
        guard let draft = await draftRepository.latest(patientID: patientID) else {
            throw ConfirmMedicalDraftError.draftNotFound
        }

        var snapshot = await medicalDataRepository.loadSnapshot()
        let newCase = MedicalCase(
            memberID: patientID,
            title: draft.title,
            chiefComplaint: "",
            diagnosis: draft.diagnosis ?? "",
            severity: "unknown",
            visitDate: draft.occurredAt,
            status: "active",
            notes: draft.summary,
            updatedAt: Date()
        )
        snapshot.medicalCases.append(newCase)
        snapshot.updatedAt = Date()
        try await medicalDataRepository.saveSnapshot(snapshot)
        await draftRepository.markConfirmed(draftID: draft.id)

        return MedicalRecord(
            id: newCase.id,
            patientID: patientID,
            title: newCase.title,
            summary: draft.summary,
            occurredAt: draft.occurredAt,
            updatedAt: newCase.updatedAt
        )
    }
}

