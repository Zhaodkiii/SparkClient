import Foundation

protocol HomeMemberRepository: Sendable {
    func refreshRemoteSnapshot() async throws
    func loadSnapshot() async -> MedicalDataSnapshot
    func createMember(
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws
    func updateMember(
        _ member: Member,
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws
    func deleteMember(_ member: Member) async throws
}
