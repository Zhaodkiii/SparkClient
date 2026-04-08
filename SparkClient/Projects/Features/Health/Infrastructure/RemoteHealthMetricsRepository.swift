import Foundation

final class RemoteHealthMetricsRepository: HealthMetricsRepository {
    private let queryAPI: SparkMedicalQueryAPI

    init(queryAPI: SparkMedicalQueryAPI) {
        self.queryAPI = queryAPI
    }

    func seedDefaultMetricsIfNeeded(for profileID: UUID) async throws {}

    func fetchRecentMetrics(for profileID: UUID, limit: Int) async throws -> [HealthMetric] {
        let rows = try await queryAPI.listHealthMetrics(profileClientUID: profileID)
        return rows
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(max(1, limit))
            .map { metric in
                HealthMetric(
                    id: UUID(),
                    profileID: metric.profileClientUID,
                    type: HealthMetricType(rawValue: metric.metricType) ?? .steps,
                    value: metric.value,
                    unit: metric.unit,
                    recordedAt: metric.recordedAt,
                    note: metric.note
                )
            }
    }
}
