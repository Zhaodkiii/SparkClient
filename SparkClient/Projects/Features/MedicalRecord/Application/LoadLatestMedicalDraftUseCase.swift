import Foundation

struct LoadLatestMedicalDraftUseCase: Sendable {
    let draftRepository: any MedicalDraftRepository

    func execute(patientID: UUID) async -> RecognizedMedicalDraft? {
        await draftRepository.latest(patientID: patientID)
    }
}

