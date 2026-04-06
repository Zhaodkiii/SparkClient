import Foundation

final class RemoteHealthMetricsRepository: HealthMetricsRepository {
    private let remoteAPI: SparkMedicalSyncAPI

    init(remoteAPI: SparkMedicalSyncAPI) {
        self.remoteAPI = remoteAPI
    }

    func seedDefaultMetricsIfNeeded(for profileID: UUID) async throws {}

    func fetchRecentMetrics(for profileID: UUID, limit: Int) async throws -> [HealthMetric] {
        let payload = try await remoteAPI.fetchSnapshot(priority: .balanced)
        return payload.healthMetrics
            .filter { $0.profileClientUID == profileID }
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
