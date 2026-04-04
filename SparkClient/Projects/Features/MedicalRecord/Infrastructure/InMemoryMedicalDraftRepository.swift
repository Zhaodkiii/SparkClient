import Foundation

actor InMemoryMedicalDraftRepository: MedicalDraftRepository {
    private var draftsByPatient: [UUID: [RecognizedMedicalDraft]] = [:]

    func save(_ draft: RecognizedMedicalDraft) async {
        var drafts = draftsByPatient[draft.patientID] ?? []
        drafts.append(draft)
        drafts.sort { $0.createdAt > $1.createdAt }
        draftsByPatient[draft.patientID] = drafts
    }

    func latest(patientID: UUID) async -> RecognizedMedicalDraft? {
        draftsByPatient[patientID]?.first
    }

    func markConfirmed(draftID: UUID) async {
        for patientID in draftsByPatient.keys {
            guard var drafts = draftsByPatient[patientID] else { continue }
            if let index = drafts.firstIndex(where: { $0.id == draftID }) {
                var updated = drafts[index]
                updated.isConfirmed = true
                drafts[index] = updated
                draftsByPatient[patientID] = drafts
                return
            }
        }
    }
}

