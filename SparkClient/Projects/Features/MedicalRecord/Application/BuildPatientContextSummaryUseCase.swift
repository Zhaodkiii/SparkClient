import Foundation

struct BuildPatientContextSummaryUseCase: Sendable {
    let repository: any MedicalRecordRepository

    func execute(patientID: Int, limit: Int = 6) async -> String {
        await repository.buildPatientContextSummary(patientID: patientID, limit: limit)
    }
}
