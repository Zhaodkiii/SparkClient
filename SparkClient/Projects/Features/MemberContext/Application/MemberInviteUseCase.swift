import Foundation

struct MemberInviteUseCase: Sendable {
    let memberAPI: SparkMedicalMemberAPI

    func fetchPending() async throws -> [SparkMedicalMemberAPI.PendingInviteItem] {
        try await memberAPI.pendingInvites()
    }

    func accept(inviteID: Int, relationship: String, customRelationship: String = "") async throws -> Member {
        let remote = try await memberAPI.acceptInvite(
            inviteID: inviteID,
            relationship: relationship,
            customRelationship: customRelationship
        )
        return remote.domainModel
    }

    func reject(inviteID: Int) async throws {
        try await memberAPI.rejectInvite(inviteID: inviteID)
    }

    func cancel(inviteID: Int) async throws {
        try await memberAPI.cancelInvite(inviteID: inviteID)
    }

    func invite(
        memberID: Int,
        channel: String,
        contact: String,
        permission: String,
        phone: String? = nil,
        countryCode: String? = nil
    ) async throws -> SparkMedicalMemberAPI.InviteResponse {
        try await memberAPI.createInvite(
            memberID: memberID,
            payload: SparkMedicalMemberAPI.InvitePayload(
                channel: channel,
                targetContact: contact,
                permission: permission,
                phone: phone,
                countryCode: countryCode
            )
        )
    }

    func fetchDetail(inviteID: Int) async throws -> SparkMedicalMemberAPI.PendingInviteItem {
        try await memberAPI.fetchInviteDetail(inviteID: inviteID)
    }
}
