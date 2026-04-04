import Foundation

protocol HealthMetricsRepository: Sendable {
    func seedDefaultMetricsIfNeeded(for profileID: UUID) async throws
    func fetchRecentMetrics(for profileID: UUID, limit: Int) async throws -> [HealthMetric]
}
