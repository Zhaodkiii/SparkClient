import Foundation

enum ManageHomeMemberError: LocalizedError {
    case relationshipUpdateFailed

    var errorDescription: String? {
        switch self {
        case .relationshipUpdateFailed:
            return L10n.text("home.members.update.relationship_failed")
        }
    }
}

/// 家庭成员增删改：直接调用 ``SparkMedicalMemberAPI``。
struct ManageHomeMemberUseCase: Sendable {
    let memberAPI: SparkMedicalMemberAPI

    func create(
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws -> Member {
        let payload = SparkMedicalMemberAPI.UpsertMemberPayload(
            name: name,
            relationship: relationship,
            gender: gender,
            birthDate: birthDate,
            bloodType: "",
            allergies: [],
            chronicConditions: [],
            notes: "",
            avatarUrl: "",
            isPrimary: false
        )
        return try await memberAPI.createMember(payload).domainModel
    }

    func update(
        member: Member,
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws {
        let payload = SparkMedicalMemberAPI.UpsertMemberPayload(
            name: name,
            relationship: relationship,
            gender: gender,
            birthDate: birthDate,
            bloodType: member.bloodType,
            allergies: member.allergies,
            chronicConditions: member.chronicConditions,
            notes: member.notes,
            avatarUrl: member.avatarUrl,
            isPrimary: member.isPrimary
        )
        try await memberAPI.updateMember(remoteID: member.id, payload: payload)
        guard let bindingID = member.binding?.bindingID, bindingID > 0 else { return }
        do {
            _ = try await memberAPI.updateBinding(bindingID: bindingID, relationship: relationship)
        } catch {
            throw ManageHomeMemberError.relationshipUpdateFailed
        }
    }

    func delete(member: Member) async throws {
        try await memberAPI.deleteMember(remoteID: member.id)
    }
}
