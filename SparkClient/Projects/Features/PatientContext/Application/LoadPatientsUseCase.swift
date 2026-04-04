import Foundation

struct LoadPatientsUseCase: Sendable {
    let repository: any PatientRepository

    func execute() async -> [Member] {
        await repository.loadPatients()
    }
}
