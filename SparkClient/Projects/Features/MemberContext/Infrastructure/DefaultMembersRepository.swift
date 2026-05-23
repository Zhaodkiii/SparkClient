import Foundation

final class DefaultMembersRepository: MembersRepository, @unchecked Sendable {
    private let medicalQueryAPI: SparkMedicalQueryAPI

    init(medicalQueryAPI: SparkMedicalQueryAPI) {
        self.medicalQueryAPI = medicalQueryAPI
    }

    func loadMembers() async -> [Member] {
        let members = (try? await medicalQueryAPI.listMembers()) ?? []
        return members.map(\.domainModel).sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPrimary && !rhs.isPrimary
        }
    }
}
