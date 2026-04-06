import Foundation

struct LoadLatestMedicalDraftUseCase: Sendable {
    let draftRepository: any MedicalDraftRepository

    func execute(patientID: Int) async -> RecognizedMedicalDraft? {
        await draftRepository.latest(patientID: patientID)
    }
}

