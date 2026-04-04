import Foundation

struct LoadMedicalRecordsUseCase: Sendable {
    let repository: any MedicalRecordRepository

    func execute(patientID: UUID, limit: Int = 20) async -> [MedicalRecord] {
        await repository.loadRecords(patientID: patientID, limit: limit)
    }
}
