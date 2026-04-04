import Foundation

struct RequestHomeHealthAuthorizationUseCase: Sendable {
    let healthDataRepository: any HomeHealthDataRepository

    func execute() async throws -> HomeDashboard.HealthAuthorizationStatus {
        try await healthDataRepository.requestAuthorizationIfNeeded()
    }
}
