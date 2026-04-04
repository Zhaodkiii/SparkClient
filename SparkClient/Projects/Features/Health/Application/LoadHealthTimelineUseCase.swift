import Foundation

struct LoadHealthTimelineUseCase: Sendable {
    let healthMetricsRepository: any HealthMetricsRepository

    func execute(profileID: UUID) async throws -> [HealthMetric] {
        try await healthMetricsRepository.fetchRecentMetrics(for: profileID, limit: 30)
    }
}
