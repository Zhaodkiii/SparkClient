import Foundation

final class DefaultPatientRepository: PatientRepository, @unchecked Sendable {
    private let medicalDataRepository: any MedicalDataRepository

    init(medicalDataRepository: any MedicalDataRepository) {
        self.medicalDataRepository = medicalDataRepository
    }

    func loadPatients() async -> [Member] {
        let snapshot = await medicalDataRepository.loadSnapshot()
        return snapshot.members.sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.isPrimary && !rhs.isPrimary
        }
    }
}
