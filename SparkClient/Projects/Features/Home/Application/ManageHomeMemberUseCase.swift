import Foundation

struct ManageHomeMemberUseCase: Sendable {
    let memberRepository: any HomeMemberRepository

    func create(
        name: String,
        relationship: String,
        age: Int,
        gender: String,
        birthDate: Date?
    ) async throws {
        try await memberRepository.createMember(
            name: name,
            relationship: relationship,
            age: age,
            gender: gender,
            birthDate: birthDate
        )
    }

    func update(
        member: Member,
        name: String,
        relationship: String,
        age: Int,
        gender: String,
        birthDate: Date?
    ) async throws {
        try await memberRepository.updateMember(
            member,
            name: name,
            relationship: relationship,
            age: age,
            gender: gender,
            birthDate: birthDate
        )
    }

    func delete(member: Member) async throws {
        try await memberRepository.deleteMember(member)
    }
}
