import Foundation

struct LoadMedicalRecordsUseCase: Sendable {
    let repository: any MedicalRecordRepository

    func execute(memberID: Int, limit: Int = 20) async -> [MedicalRecord] {
        await repository.loadRecords(memberID: memberID, limit: limit)
    }
}
