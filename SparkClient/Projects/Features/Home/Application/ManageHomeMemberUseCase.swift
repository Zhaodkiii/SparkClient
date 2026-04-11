import Foundation

/// 家庭成员增删改：直接调用 ``SparkMedicalMemberAPI``。
struct ManageHomeMemberUseCase: Sendable {
    let memberAPI: SparkMedicalMemberAPI

    func create(
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
            bloodType: "",
            allergies: [],
            chronicConditions: [],
            notes: "",
            avatarUrl: "",
            isPrimary: false
        )
        _ = try await memberAPI.createMember(payload)
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
        _ = try await memberAPI.updateMember(remoteID: member.id, payload: payload)
    }

    func delete(member: Member) async throws {
        try await memberAPI.deleteMember(remoteID: member.id)
    }
}
