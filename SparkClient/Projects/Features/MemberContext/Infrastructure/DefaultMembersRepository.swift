import Foundation

final class DefaultMembersRepository: MembersRepository, @unchecked Sendable {
    private let medicalQueryAPI: SparkMedicalQueryAPI

    init(medicalQueryAPI: SparkMedicalQueryAPI) {
        self.medicalQueryAPI = medicalQueryAPI
    }

    func loadMembers() async -> [Member] {
        let members = (try? await medicalQueryAPI.listMembers()) ?? []
        return members.map {
            Member(
                id: $0.id,
                name: $0.name,
                gender: $0.gender,
                relationship: $0.relationship,
                birthDate: $0.birthDate,
                bloodType: $0.bloodType,
                allergies: $0.allergies,
                chronicConditions: $0.chronicConditions,
                notes: $0.notes,
                avatarUrl: $0.avatarUrl,
                isPrimary: $0.isPrimary,
                updatedAt: $0.updatedAt
            )
        }.sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPrimary && !rhs.isPrimary
        }
    }
}
