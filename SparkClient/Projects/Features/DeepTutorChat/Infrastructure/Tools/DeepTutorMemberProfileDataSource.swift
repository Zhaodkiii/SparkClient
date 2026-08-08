import Foundation

protocol DeepTutorMemberProfileToolDataSource: Sendable {
    func fetchMemberCompleteData(memberID: Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData
}

final class DeepTutorMemberProfileDataSource: DeepTutorMemberProfileToolDataSource, @unchecked Sendable {
    private let medicalQueryAPI: SparkMedicalQueryAPI

    init(medicalQueryAPI: SparkMedicalQueryAPI) {
        self.medicalQueryAPI = medicalQueryAPI
    }

    func fetchMemberCompleteData(memberID: Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData {
        try await medicalQueryAPI.fetchMemberCompleteData(memberID: memberID)
    }
}
