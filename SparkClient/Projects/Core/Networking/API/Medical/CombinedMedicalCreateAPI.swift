import Foundation

// MARK: - 请求模型（与后端 CombinedMedicalCreateAPIView 对齐）

/// 成员创建请求（用于创建新成员）
struct MemberCreateRequest: Encodable, Sendable {
    let name: String
    let gender: String?
    let birthDate: String?
    let relationship: String?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case gender
        case birthDate = "birth_date"
        case relationship
        case extra
    }
}

/// 成员创建请求（带 ID，用于校验或更新现有成员）
struct MemberCreateRequestWithId: Encodable, Sendable {
    let id: Int?
    let name: String?
    let gender: String?
    let birthDate: String?
    let relationship: String?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case gender
        case birthDate = "birth_date"
        case relationship
        case extra
    }
}

/// 病历创建请求（与 `MedicalCase` 字段对齐）
struct MedicalCaseCreateRequest: Encodable, Sendable {
    let title: String
    let hospitalName: String?
    let diagnosisSummary: String?
    let ageAtVisit: Int?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case title
        case hospitalName = "hospital_name"
        case diagnosisSummary = "diagnosis_summary"
        case ageAtVisit = "age_at_visit"
        case extra
    }
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

    enum CodingKeys: String, CodingKey {
        case name
        case code
        case severity
        case startedAt = "started_at"
        case durationValue = "duration_value"
        case durationUnit = "duration_unit"
        case bodyPart = "body_part"
        case notes
    }
}

/// 就诊创建请求（与 `Visit` 字段对齐）
struct VisitCreateRequest: Encodable, Sendable {
    let visitType: String?
    let visitedAt: String?
    let department: String?
    let doctorName: String?
    let visitNo: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case visitType = "visit_type"
        case visitedAt = "visited_at"
        case department
        case doctorName = "doctor_name"
        case visitNo = "visit_no"
        case notes
    }
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

    enum CodingKeys: String, CodingKey {
        case procedureName = "procedure_name"
        case procedureCode = "procedure_code"
        case site
        case performedAt = "performed_at"
        case surgeon
        case anesthesiaType = "anesthesia_type"
        case incisionLevel = "incision_level"
        case asaClass = "asa_class"
        case notes
    }
}

/// 随访创建请求（与 `FollowUp` 字段对齐）
struct FollowUpCreateRequest: Encodable, Sendable {
    let plannedAt: String?
    let completedAt: String?
    let status: String?
    let method: String?
    let outcome: String?
    let nextAction: String?

    enum CodingKeys: String, CodingKey {
        case plannedAt = "planned_at"
        case completedAt = "completed_at"
        case status
        case method
        case outcome
        case nextAction = "next_action"
    }
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

    enum CodingKeys: String, CodingKey {
        case category
        case subCategory = "sub_category"
        case itemName = "item_name"
        case itemCode = "item_code"
        case resultValue = "result_value"
        case unit
        case referenceRange = "reference_range"
        case flag
        case resultAt = "result_at"
        case modality
        case bodyPart = "body_part"
        case diagnosis
        case sortOrder = "sort_order"
        case extra
    }
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

    enum CodingKeys: String, CodingKey {
        case category
        case itemName = "item_name"
        case findings
        case impression
        case performedAt = "performed_at"
        case organizationName = "organization_name"
        case doctorName = "doctor_name"
        case details
    }
}

/// 用药项创建请求（内嵌于处方批次）
struct PrescriptionMedicationRequest: Encodable, Sendable {
    let genericName: String?
    let brandName: String?
    let drugName: String?
    let dosageForm: String?
    let strength: String?
    let route: String?
    let dosePerTime: String?
    let doseValue: Double?
    let doseUnit: String?
    let frequencyCode: String?
    let period: String?
    let timesPerPeriod: Int?
    let frequencyText: String?
    let durationDays: Int?
    let instructions: String?
    let sortOrder: Int?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case genericName = "generic_name"
        case brandName = "brand_name"
        case drugName = "drug_name"
        case dosageForm = "dosage_form"
        case strength
        case route
        case dosePerTime = "dose_per_time"
        case doseValue = "dose_value"
        case doseUnit = "dose_unit"
        case frequencyCode = "frequency_code"
        case period
        case timesPerPeriod = "times_per_period"
        case frequencyText = "frequency_text"
        case durationDays = "duration_days"
        case instructions
        case sortOrder = "sort_order"
        case extra
    }
}

/// 处方批次创建请求（与 `PrescriptionBatch` 字段对齐）
struct PrescriptionBatchCreateRequest: Encodable, Sendable {
    let prescriberName: String?
    let institutionName: String?
    let prescribedAt: String?
    let diagnosis: String?
    let batchNo: String?
    let status: String?
    let medications: [PrescriptionMedicationRequest]?

    enum CodingKeys: String, CodingKey {
        case prescriberName = "prescriber_name"
        case institutionName = "institution_name"
        case prescribedAt = "prescribed_at"
        case diagnosis
        case batchNo = "batch_no"
        case status
        case medications
    }
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

    /// 处方批次列表（可选，推荐）
    let prescriptionBatches: [PrescriptionBatchCreateRequest]?

    /// 源文件 ID 列表（用于绑定附件）
    let sourceFileIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case member
        case medicalCase = "medical_case"
        case symptom
        case visit
        case surgery
        case followUp = "follow_up"
        case examinationReports = "examination_reports"
        case prescriptionBatches = "prescription_batches"
        case sourceFileIds = "source_file_ids"
    }
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
    let prescriptionBatchIds: [Int]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case medicalCaseId = "medical_case_id"
        case symptomId = "symptom_id"
        case visitId = "visit_id"
        case surgeryId = "surgery_id"
        case followUpId = "follow_up_id"
        case examinationReportIds = "examination_report_ids"
        case prescriptionBatchIds = "prescription_batch_ids"
        case createdAt = "created_at"
    }
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
