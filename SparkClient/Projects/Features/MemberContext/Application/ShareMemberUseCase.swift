import Foundation

struct ShareMemberUseCase: Sendable {
    let memberAPI: SparkMedicalMemberAPI

    func generateQRShare(memberID: Int, permission: String = "edit") async throws -> SparkMedicalMemberAPI.ShareTicketResponse {
        try await memberAPI.generateShareTicket(memberID: memberID, channel: "qr", permission: permission)
    }

    func generateNearbyShare(memberID: Int, permission: String = "edit") async throws -> SparkMedicalMemberAPI.ShareTicketResponse {
        try await memberAPI.generateShareTicket(memberID: memberID, channel: "nearby", permission: permission)
    }

    func resolve(ticket: String) async throws -> SparkMedicalMemberAPI.ShareResolveResponse {
        try await memberAPI.resolveShareTicket(ticket)
    }

    func accept(ticket: String, relationship: String, customRelationship: String = "") async throws -> Member {
        let remote = try await memberAPI.acceptShareTicket(
            ticket,
            relationship: relationship,
            customRelationship: customRelationship
        )
        return remote.domainModel
    }
}
