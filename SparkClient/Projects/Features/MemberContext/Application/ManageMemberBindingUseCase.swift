import Foundation

struct ManageMemberBindingUseCase: Sendable {
    let memberAPI: SparkMedicalMemberAPI

    func fetchDetail(memberID: Int) async throws -> SparkMedicalMemberAPI.MemberDetailResponse {
        try await memberAPI.fetchMemberDetail(memberID: memberID)
    }

    func updateRelationship(bindingID: Int, relationship: String) async throws -> Member {
        let remote = try await memberAPI.updateBinding(bindingID: bindingID, relationship: relationship)
        return remote.domainModel
    }

    func unbind(bindingID: Int) async throws {
        try await memberAPI.unbind(bindingID: bindingID)
    }
}
