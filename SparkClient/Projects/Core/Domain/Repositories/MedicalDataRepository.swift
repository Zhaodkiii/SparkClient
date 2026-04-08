import Foundation

// MARK: - Synced health metrics

/// 与服务端同步的健康指标样本（时间序列），按客户端 `profileID` 归属，**不**绑定家庭成员 `Member`。
///
/// 与病例、检查报告等「按成员」的医疗数据并列存在于 `MedicalDataSnapshot` 中；首页 Apple Health（HealthKit）走独立仓库，与此类型数据源不同。
struct SyncedHealthMetric: Codable, Equatable, Sendable, Identifiable {
    /// 本地稳定标识。
    let id: UUID
    /// 所属用户档案（Spark 侧 `profile_client_uid`）。
    let profileID: UUID
    let type: HealthMetricType
    let value: Double
    let unit: String
    let recordedAt: Date
    let note: String?
    let updatedAt: Date
}

// MARK: - Medical data snapshot

/// 本地医疗域聚合快照：家庭成员 + 各成员关联的病历实体 + 档案维度的同步健康指标。
struct MedicalDataSnapshot: Codable, Equatable, Sendable {
    var members: [Member]
    var medicalCases: [MedicalCase]
    var symptoms: [Symptom]
    var visits: [Visit]
    var surgeries: [Surgery]
    var followUps: [FollowUp]
    var healthExamReports: [HealthExamReport]
    var examinationReports: [ExaminationReport]
    var medExamDetails: [MedExamDetail]
    var medicalReports: [MedicalReport]
    var prescriptionBatches: [PrescriptionBatch]
    var medications: [Medication]
    var medicationTakenRecords: [MedicationTakenRecord]
    var healthMetrics: [SyncedHealthMetric]
    var updatedAt: Date

    /// 空快照，用于占位或解析失败时的安全回退。
    static let empty = MedicalDataSnapshot(
        members: [],
        medicalCases: [],
        symptoms: [],
        visits: [],
        surgeries: [],
        followUps: [],
        healthExamReports: [],
        examinationReports: [],
        medExamDetails: [],
        medicalReports: [],
        prescriptionBatches: [],
        medications: [],
        medicationTakenRecords: [],
        healthMetrics: [],
        updatedAt: Date()
    )
}

// MARK: - MedicalDataRepository

/// 医疗快照仓储抽象（成员、病历、报告、处方及 `healthMetrics`）。
///
/// 约定：服务端为主数据源；客户端不再对医疗快照做本地数据库持久化。
protocol MedicalDataRepository: Sendable {
    /// 读取当前医疗快照（通常来自服务端）。
    func loadSnapshot() async -> MedicalDataSnapshot
    /// 保存完整快照（实现侧通常映射为服务端 upsert）。
    func saveSnapshot(_ snapshot: MedicalDataSnapshot) async throws
    /// 从服务端拉取最新快照（是否缓存由实现决定）。
    func pullSnapshotFromServer(priority: CloudSyncPriority) async throws
}
