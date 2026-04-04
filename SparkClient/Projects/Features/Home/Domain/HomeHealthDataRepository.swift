import Foundation

protocol HomeHealthDataRepository: Sendable {
    func currentAuthorizationStatus() async -> HomeDashboard.HealthAuthorizationStatus
    func requestAuthorizationIfNeeded() async throws -> HomeDashboard.HealthAuthorizationStatus
    func fetchHealthBasics() async throws -> [HomeDashboard.HealthBasicItem]
}
