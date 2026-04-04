import Foundation

enum HealthMetricType: String, Codable, CaseIterable, Equatable, Sendable {
    case steps
    case sleep
    case heartRate
    case weight
}

struct HealthMetric: Equatable, Sendable, Identifiable {
    let id: UUID
    let profileID: UUID
    let type: HealthMetricType
    let value: Double
    let unit: String
    let recordedAt: Date
    let note: String?
}
