import Foundation

struct BuildMemberContextSummaryUseCase: Sendable {
    let repository: any MedicalRecordRepository

    func execute(memberID: Int, limit: Int = 6) async -> String {
        await repository.buildMemberContextSummary(memberID: memberID, limit: limit)
    }
}
