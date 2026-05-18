import Foundation

// MARK: - 请求模型（与后端 CombinedMedicalCreateAPIView 对齐）

/// 成员创建请求（用于创建新成员）
struct MemberCreateRequest: Encodable, Sendable {
    let name: String
    let gender: String?
    let birthDate: String?
    let relationship: String?
    let extra: [String: String]?

}

/// 成员创建请求（带 ID，用于校验或更新现有成员）
struct MemberCreateRequestWithId: Encodable, Sendable {
    let id: Int?
    let name: String?
    let gender: String?
    let birthDate: String?
    let relationship: String?
    let extra: [String: String]?

}

/// 病历创建请求（与 `MedicalCase` 字段对齐）
struct MedicalCaseCreateRequest: Encodable, Sendable {
    let title: String
    let hospitalName: String?
    let diagnosisSummary: String?
    let ageAtVisit: Int?
    let extra: [String: String]?

}

/// 症状创建请求（与 `Symptom` 字段对齐）
struct SymptomCreateRequest: Encodable, Sendable {
    let name: String
    let code: String?
    let severity: String?
    let startedAt: String?
    let durationValue: Int?
    let durationUnit: String?
    let bodyPart: String?
    let notes: String?

}

/// 就诊创建请求（与 `Visit` 字段对齐）
struct VisitCreateRequest: Encodable, Sendable {
    let visitType: String?
    let visitedAt: String?
    let department: String?
    let doctorName: String?
    let visitNo: String?
    let notes: String?

}

/// 手术创建请求（与 `Surgery` 字段对齐）
struct SurgeryCreateRequest: Encodable, Sendable {
    let procedureName: String
    let procedureCode: String?
    let site: String?
    let performedAt: String?
    let surgeon: String?
    let anesthesiaType: String?
    let incisionLevel: String?
    let asaClass: String?
    let notes: String?

}

/// 随访创建请求（与 `FollowUp` 字段对齐）
struct FollowUpCreateRequest: Encodable, Sendable {
    let plannedAt: String?
    let completedAt: String?
    let status: String?
    let method: String?
    let outcome: String?
    let nextAction: String?

}

/// 检查报告明细项创建请求
struct ExaminationReportDetailRequest: Encodable, Sendable {
    let category: String
    let subCategory: String?
    let itemName: String?
    let itemCode: String?
    let resultValue: String
    let unit: String?
    let referenceRange: String?
    let flag: String?
    let resultAt: String?
    let modality: String?
    let bodyPart: String?
    let diagnosis: String?
    let sortOrder: Int?
    let extra: [String: String]?

}

/// 检查报告创建请求（与 `ExaminationReport` 字段对齐）
struct ExaminationReportCreateRequest: Encodable, Sendable {
    let category: String
    let itemName: String?
    let findings: String?
    let impression: String?
    let performedAt: String?
    let organizationName: String?
    let doctorName: String?
    let details: [ExaminationReportDetailRequest]?

}

/// 组合创建处方请求（与 `Prescription` 字段对齐，内含处方下的 `MedicationPlan` 行）
struct PrescriptionCreateRequest: Encodable, Sendable {
    let prescriberName: String?
    let institutionName: String?
    let prescribedAt: String?
    let diagnosis: String?
    let prescriptionNo: String?
    let status: String?
    let extra: [String: String]?
    let medicationPlans: [SparkMedicalWorkflowAPI.MedicationPlanBundleItemPayload]

}

/// 组合创建请求（一次性创建所有医疗信息）
/// 参考 HealthClient 的 SeverMedicalCreateRequest 模式
struct CombinedMedicalCreateRequest: Encodable, Sendable {
    /// 成员信息（必填）
    /// - 若带 id 则校验存在与归属；否则创建新成员
    let member: MemberCreateRequestWithId

    /// 病历信息（必填）
    let medicalCase: MedicalCaseCreateRequest

    /// 症状信息（可选）
    let symptom: SymptomCreateRequest?

    /// 就诊信息（可选）
    let visit: VisitCreateRequest?

    /// 手术信息（可选）
    let surgery: SurgeryCreateRequest?

    /// 随访信息（可选）
    let followUp: FollowUpCreateRequest?

    /// 检查报告列表（可选）
    let examinationReports: [ExaminationReportCreateRequest]?

    /// 处方列表（可选），每条处方内含用药计划
    let prescriptions: [PrescriptionCreateRequest]?

    /// 源文件 ID 列表（用于绑定附件）
    let sourceFileIds: [Int]?

}

// MARK: - 响应模型

/// 组合创建响应（与后端 CombinedMedicalCreateAPIView 返回结构对齐）
struct CombinedMedicalCreateResponse: Decodable, Sendable {
    let memberId: Int
    let medicalCaseId: Int
    let symptomId: Int?
    let visitId: Int?
    let surgeryId: Int?
    let followUpId: Int?
    let examinationReportIds: [Int]?
    let prescriptionIds: [Int]?
    let medicineBoxIds: [Int]?
    let medicationPlanIds: [Int]?
    let createdAt: String

}

// MARK: - API

/// 组合创建医疗记录 API
/// 一次性创建成员、病历及所有相关信息（症状、就诊、手术、随访、检查报告、处方等）
/// 参考 HealthClient 的 createSeverMedical 模式
struct SparkCombinedMedicalCreateAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    /// 组合创建医疗记录（一次性创建成员、病历及所有相关信息）
    /// - Parameter request: 组合创建请求
    /// - Returns: 创建结果（包含所有创建的对象 ID）
    func createCombinedMedical(_ request: CombinedMedicalCreateRequest) async throws -> CombinedMedicalCreateResponse {
        let op = CacheableSparkNetworkOperation(
            name: "CombinedMedical.Create",
            apiName: "CombinedMedicalCreateAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/medical/combined-create/",
                body: .json(AnyEncodable(request)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "medical.combined-create",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(op)
        return try APIResponseDecoder.decodeWrappedDataOrDirect(CombinedMedicalCreateResponse.self, from: response)
    }
}
