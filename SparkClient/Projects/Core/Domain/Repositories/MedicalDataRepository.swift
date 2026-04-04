import Foundation

struct SyncedHealthMetric: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let profileID: UUID
    let type: HealthMetricType
    let value: Double
    let unit: String
    let recordedAt: Date
    let note: String?
    let updatedAt: Date
}

struct MedicalDataSnapshot: Codable, Equatable, Sendable {
    var members: [Member]
    var medicalCases: [MedicalCase]
    var examinationReports: [ExaminationReport]
    var medicalReports: [MedicalReport]
    var prescriptions: [Prescription]
    var healthMetrics: [SyncedHealthMetric]
    var updatedAt: Date

    static let empty = MedicalDataSnapshot(
        members: [],
        medicalCases: [],
        examinationReports: [],
        medicalReports: [],
        prescriptions: [],
        healthMetrics: [],
        updatedAt: Date()
    )
}

protocol MedicalDataRepository: Sendable {
    func loadSnapshot() async -> MedicalDataSnapshot
    func saveSnapshot(_ snapshot: MedicalDataSnapshot) async throws
    func uploadSnapshotToServer(priority: CloudSyncPriority) async throws
    func pullSnapshotFromServer(priority: CloudSyncPriority) async throws
}
