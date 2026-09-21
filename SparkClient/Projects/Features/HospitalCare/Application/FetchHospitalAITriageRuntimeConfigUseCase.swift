import Foundation

nonisolated final class FetchHospitalAITriageRuntimeConfigUseCase: @unchecked Sendable {
    private let remoteAPI: any HospitalCareRemoteServing

    init(remoteAPI: any HospitalCareRemoteServing) {
        self.remoteAPI = remoteAPI
    }

    func execute(
        hospitalID: UUID,
        memberID: Int,
        accountID: Int64
    ) async throws -> HospitalAgentRuntimeConfig {
        let dto = try await remoteAPI.fetchAITriageRuntimeConfig(hospitalID: hospitalID, memberID: memberID)
        guard let config = HospitalAgentRuntimeConfig.makeFromTriage(
            dto: dto,
            expectedMemberID: memberID,
            expectedHospitalID: hospitalID
        ) else {
            throw HospitalAgentRuntimeConfigError.runtimeConfigInvalid
        }
        return config
    }
}
