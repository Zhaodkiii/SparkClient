import Foundation

/// 医疗工作流「单点保存」网络层封装。
///
/// 与全量快照上传不同，本 API 按业务实体（病历摘要、体检、检查报告、处方、药品等）分别 POST 保存，
/// 减轻带宽与冲突风险；所有接口均需登录（`requiresAuth: true`），且走统一的高优先级串行键避免并发写乱序。
struct SparkMedicalWorkflowAPI {
    /// 后端配置（基址、鉴权、执行器等），由上层注入。
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    /// 病历类文档（case document）保存请求体，对应「病例/就诊记录」维度的摘要信息。
    /// 字段与 `MedicalCase` / `MedicalCaseSerializer` 对齐。
    nonisolated struct CaseSavePayload: Encodable, Sendable {
        /// 关联的家庭成员服务端 ID（`MedicalMember`）。
        let member: Int
        /// 记录类型编码，与后端 `record_type` 约定一致（如门诊、住院等）。
        let recordType: String
        /// 业务状态码：`MedicalCase.Status` — 1 draft，2 submitted，3 archived。
        let status: Int
        /// 展示用标题。
        let title: String
        /// 就诊医院名称（`hospital_name`）。
        let hospitalName: String?
        /// 就诊时年龄（`age_at_visit`）。
        let ageAtVisit: Int?
        /// 诊断摘要文本（`diagnosis_summary`）。
        let diagnosisSummary: String
        /// 扩展键值对，供未建模字段或灰度字段透传。
        let extra: [String: String]

    }

    /// 体检报告保存请求体。
    nonisolated struct HealthExamSavePayload: Encodable, Sendable {
        /// 关联成员 ID。
        let member: Int
        /// 体检机构名称。
        let institutionName: String
        /// 报告编号（机构内唯一或展示用）。
        let reportNo: String
        /// 体检日期，一般为 ISO8601 日期字符串或后端约定格式；可选表示未知。
        let examDate: String?
        /// 体检类型枚举整型值，与后端 `exam_type` 对齐。
        let examType: Int
        /// 报告摘要；可选。
        let summary: String?
        /// 数据来源（如手动录入、OCR、导入等），整型与后端枚举一致。
        let source: Int
        /// OCR 原始键值对，便于追溯或二次校对；无 OCR 时可传 `nil`。
        let rawOCR: [String: String]?
        /// 记录状态。
        let status: Int
        /// 扩展字段。
        let extra: [String: String]
        /// 子项目明细行；结构与检查报告明细保持一致。
        let details: [MedicalReportDetailPayload]
        /// 已上传文件 ID，服务端在落库后绑定到该体检报告（与 ``HealthExamWorkflowSaveView`` 的 `file_ids` 一致）。
        let fileIds: [Int]

    }

    /// 检查/检验报告中的「明细行」：单项结果（如血常规某一指标、影像所见子项等）。
    nonisolated struct MedicalReportDetailPayload: Encodable, Sendable {
        /// 大类（如检验、影像）。
        let category: String
        /// 子类（如血常规、CT）。
        let subCategory: String
        /// 项目名称（展示用）。
        let itemName: String
        /// 项目编码（若无可与名称相同或留空规则由产品约定）。
        let itemCode: String
        /// 结果值文本（含定性描述时亦放此字段）。
        let resultValue: String
        /// 单位。
        let unit: String
        /// 参考范围描述。
        let referenceRange: String
        /// 异常标记（如 H/L/正常），与后端约定字符串。
        let flag: String
        /// 该明细结果对应的时间点；可选。
        let resultAt: String?
        /// 检查模态（如 CT、MRI）；影像类常用。
        let modality: String
        /// 检查部位。
        let bodyPart: String
        /// 该明细关联的诊断或结论片段。
        let diagnosis: String
        /// 明细级扩展。
        let extra: [String: String]
        /// 列表排序序号，越小越靠前（与 UI 一致）。
        let sortOrder: Int

    }

    /// 检查/检验报告主记录保存请求体（含多条 `details`）。
    nonisolated struct MedicalReportSavePayload: Encodable, Sendable {
        /// 关联成员 ID。
        let member: Int
        /// 若报告挂在某次就诊/病历下，传服务端病历 ID；独立报告可传 `nil`。
        let medicalCase: Int?
        /// 报告分类。
        let category: String
        /// 报告子类。
        let subCategory: String
        /// 报告主名称/检查项目名称。
        let itemName: String
        /// 检查执行时间。
        let performedAt: String?
        /// 报告出具时间。
        let reportedAt: String?
        /// 医疗机构名称；可选。
        let organizationName: String?
        /// 科室名称。
        let departmentName: String
        /// 医生姓名。
        let doctorName: String
        /// 所见/检查描述。
        let findings: String
        /// 印象/结论。
        let impression: String
        /// 模态。
        let modality: String
        /// 部位。
        let bodyPart: String
        /// 主诊断或综合诊断文本。
        let diagnosis: String
        /// 关联上传文件 ID 列表。
        let fileIds: [Int]
        /// 明细行数组，与列表展示顺序一致。
        let details: [MedicalReportDetailPayload]

    }

    /// 症状新建请求体（表单创建专用）。
    nonisolated struct SymptomCreatePayload: Encodable, Sendable {
        let member: Int
        let medicalCase: Int?
        let name: String
        let code: String?
        let severity: String?
        let startedAt: String?
        let durationValue: Int?
        let durationUnit: String?
        let bodyPart: String?
        let notes: String?
        let fileIds: [Int]

    }

    /// 就诊新建请求体（表单创建专用）。
    nonisolated struct VisitCreatePayload: Encodable, Sendable {
        let member: Int
        let medicalCase: Int?
        let visitType: String?
        let visitedAt: String?
        let department: String?
        let doctorName: String?
        let visitNo: String?
        let notes: String?
        let fileIds: [Int]

    }

    /// 手术新建请求体（表单创建专用）。
    nonisolated struct SurgeryCreatePayload: Encodable, Sendable {
        let member: Int
        let medicalCase: Int?
        let procedureName: String
        let procedureCode: String?
        let site: String?
        let performedAt: String?
        let surgeon: String?
        let anesthesiaType: String?
        let incisionLevel: String?
        let asaClass: String?
        let notes: String?
        let extra: [String: String]
        let fileIds: [Int]

    }

    /// 随访新建请求体（表单创建专用）。
    nonisolated struct FollowUpCreatePayload: Encodable, Sendable {
        let member: Int
        let medicalCase: Int?
        let plannedAt: String?
        let completedAt: String?
        let status: String?
        let method: String?
        let outcome: String?
        let nextAction: String?
        let fileIds: [Int]

    }

    nonisolated struct MemberMedicalProfileSavePayload: Encodable, Sendable {
        let member: Int
        let chronicConditions: [String]
        let allergies: [String]
        let allergyDetails: [String: SparkMedicalSyncAPI.RemoteAllergyDetail]
        let allergyHistory: String
        let familyHistory: [SparkMedicalSyncAPI.RemoteFamilyHistoryRecord]
        let smokingProfile: SparkMedicalSyncAPI.RemoteSmokingProfile
        let drinkingProfile: SparkMedicalSyncAPI.RemoteDrinkingProfile
        let exerciseProfile: SparkMedicalSyncAPI.RemoteExerciseProfile
        let sleepHours: Double?
        let examFocus: [String]
        let symptomFollowUpFocus: [String]
        let notes: String
        let extra: [String: String]
    }

    nonisolated struct MemberModuleSettingSavePayload: Encodable, Sendable {
        let member: Int
        let moduleCode: String
        let isEnabled: Bool
        let isCompleted: Bool
        let displayOrder: Int
        let summaryText: String
        let detailData: [String: String]
        let completedAt: Date?
        let extra: [String: String]
    }

    nonisolated struct MemberMedicalKeyIndicatorDetailSavePayload: Encodable, Sendable {
        let category: String
        let subCategory: String
        let itemName: String
        let itemCode: String
        let resultValue: String
        let unit: String
        let referenceRange: String
        let flag: String
        let resultAt: Date?
        let modality: String
        let bodyPart: String
        let diagnosis: String
        let extra: [String: String]
        let sortOrder: Int
    }

    nonisolated struct MemberMedicalKeyIndicatorRecordSavePayload: Encodable, Sendable {
        let member: Int
        let source: String
        let scenario: String
        let recordedAt: Date?
        let qaSessionId: String
        let title: String
        let summary: String
        let extra: [String: String]
        let details: [MemberMedicalKeyIndicatorDetailSavePayload]
    }

    nonisolated struct MedicationPlanBundleSavePayload: Encodable, Sendable {
        let member: Int
        let medicalCase: Int?
        let prescriptionID: Int?
        let prescription: PrescriptionPayload?
        let items: [MedicationPlanBundleItemPayload]
        let fileIds: [Int]

    }

    nonisolated struct PrescriptionPayload: Encodable, Sendable {
        let medicalCase: Int?
        let prescriberName: String?
        let institutionName: String?
        let prescribedAt: String?
        let diagnosis: String?
        let prescriptionNo: String?
        let status: String
        let extra: [String: String]

    }

    nonisolated struct MedicationPlanBundleItemPayload: Encodable, Sendable {
        let medicineBoxID: Int?
        let medicineBox: MedicineBoxPayload?
        let drugName: String
        let dosePerTime: String
        let doseValue: String?
        let doseUnit: String
        let frequencyType: String
        let everyNDays: Int?
        let weeklyWeekdays: [Int]
        let frequencyText: String
        let reminderTimes: [ReminderTime]
        let startDate: String
        let endDate: String?
        let instructions: String
        let reminderEnabled: Bool
        let status: String
        let extra: [String: String]
        let fileIds: [Int]

        enum CodingKeys: String, CodingKey {
            case medicineBoxID = "medicine_box_id"
            case medicineBox = "medicine_box"
            case drugName = "drug_name"
            case dosePerTime = "dose_per_time"
            case doseValue = "dose_value"
            case doseUnit = "dose_unit"
            case frequencyType = "frequency_type"
            case everyNDays = "every_n_days"
            case weeklyWeekdays = "weekly_weekdays"
            case frequencyText = "frequency_text"
            case reminderTimes = "reminder_times"
            case startDate = "start_date"
            case endDate = "end_date"
            case instructions
            case reminderEnabled = "reminder_enabled"
            case status
            case extra
            case fileIds = "file_ids"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(medicineBoxID, forKey: .medicineBoxID)
            try container.encodeIfPresent(medicineBox, forKey: .medicineBox)
            try container.encode(drugName, forKey: .drugName)
            try container.encode(dosePerTime, forKey: .dosePerTime)
            try container.encodeIfPresent(doseValue, forKey: .doseValue)
            try container.encode(doseUnit, forKey: .doseUnit)
            try container.encode(frequencyType, forKey: .frequencyType)
            try container.encodeIfPresent(everyNDays, forKey: .everyNDays)
            try container.encode(weeklyWeekdays, forKey: .weeklyWeekdays)
            try container.encode(frequencyText, forKey: .frequencyText)
            try container.encode(reminderTimes, forKey: .reminderTimes)
            try container.encode(startDate, forKey: .startDate)
            try container.encodeIfPresent(endDate, forKey: .endDate)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(reminderEnabled, forKey: .reminderEnabled)
            try container.encode(status, forKey: .status)
            try container.encode(extra, forKey: .extra)
            try container.encode(fileIds, forKey: .fileIds)
        }
    }

    /// 药箱创建/更新请求体（与 ``MedicineBoxSerializer`` 对齐；编码使用 ``JSONEncoder.medicalAPI`` → snake_case）。
    nonisolated struct MedicineBoxWritePayload: Encodable, Sendable {
        let member: Int?
        let entryMemberID: Int
        let medicineName: String
        let medicineType: String?
        let brandName: String
        let dosageForm: String
        let strength: String
        let doseUnit: String
        let totalQuantity: Double?
        let expireDate: String?
        let notes: String
        let extra: [String: String]
        let fileIds: [Int]
    }

    /// 用药计划 bundle 内嵌药箱字段（无 member / entryMemberID）。
    nonisolated struct MedicineBoxPayload: Encodable, Sendable {
        let medicineType: String?
        let medicineName: String
        let brandName: String
        let dosageForm: String
        let strength: String
        let doseUnit: String
        let totalQuantity: Double?
        let expireDate: String?
        let notes: String
        let extra: [String: String]
        let fileIds: [Int]
    }

    /// 通用「仅返回 id」的响应解码结构。
    private struct IDResponse: Decodable { let id: Int }
    struct MedicationPlanBundleSaveResponse: Decodable, Sendable {
        let id: Int
        let prescriptionId: Int?
    }

    nonisolated struct PrescriptionBatchSavePayload: Encodable, Sendable {
        let member: Int
        let prescriptions: [PrescriptionCreateRequest]
    }

    struct PrescriptionBatchSaveResponse: Decodable, Sendable {
        let memberId: Int
        let prescriptionIds: [Int]
        let medicineBoxIds: [Int]
        let medicationPlanIds: [Int]
    }

    /// 保存病历类文档；成功返回新建或更新后的记录 ID。
    func saveCase(_ payload: CaseSavePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/case-documents/save/", body: payload, decode: IDResponse.self).id
    }

    /// 新建症状；成功返回症状明细与重算后的成员画像摘要。
    func createSymptom(_ payload: SymptomCreatePayload) async throws -> SparkMedicalSyncAPI.SymptomMutationResponse {
        try await post(path: "/api/v1/medical/workflows/symptoms/create/", body: payload, decode: SparkMedicalSyncAPI.SymptomMutationResponse.self)
    }

    /// 删除症状；成功返回删除结果与重算后的成员画像摘要。
    func deleteSymptom(id: Int) async throws -> SparkMedicalSyncAPI.SymptomMutationResponse {
        let q = kindQueryItems(.symptoms, extra: [])
        let response = try await executeRaw(
            method: .delete,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: nil,
            allowETag: false,
            serialKey: "medical.resource.delete.symptoms.\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
        return try APIResponseDecoder.decodeWrappedData(SparkMedicalSyncAPI.SymptomMutationResponse.self, from: response, decoder: .medicalAPI)
    }

    /// 更新症状；成功返回症状明细与重算后的成员画像摘要。
    func updateSymptom<B: Encodable & Sendable>(id: Int, body: B) async throws -> SparkMedicalSyncAPI.SymptomMutationResponse {
        let q = kindQueryItems(.symptoms, extra: [])
        return try await request(
            method: .patch,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: SparkMedicalSyncAPI.SymptomMutationResponse.self,
            allowETag: false,
            serialKey: "medical.resource.update.symptoms.\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    /// 新建用药计划；成功返回计划明细与重算后的成员画像摘要。
    func createMedicationPlan<B: Encodable & Sendable>(_ body: B) async throws -> SparkMedicalSyncAPI.MedicationMutationResponse {
        let q = kindQueryItems(.medicationPlans, extra: [])
        return try await request(
            method: .post,
            path: Self.resourceCollectionPath,
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: SparkMedicalSyncAPI.MedicationMutationResponse.self,
            allowETag: false,
            serialKey: "medical.resource.create.medication_plans",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    /// 更新用药计划；成功返回计划明细与重算后的成员画像摘要。
    func updateMedicationPlan<B: Encodable & Sendable>(id: Int, body: B) async throws -> SparkMedicalSyncAPI.MedicationMutationResponse {
        let q = kindQueryItems(.medicationPlans, extra: [])
        return try await request(
            method: .patch,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: SparkMedicalSyncAPI.MedicationMutationResponse.self,
            allowETag: false,
            serialKey: "medical.resource.update.medication_plans.\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    /// 删除用药计划；成功返回删除结果与重算后的成员画像摘要。
    func deleteMedicationPlan(id: Int) async throws -> SparkMedicalSyncAPI.MedicationMutationResponse {
        let q = kindQueryItems(.medicationPlans, extra: [])
        let response = try await executeRaw(
            method: .delete,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: nil,
            allowETag: false,
            serialKey: "medical.resource.delete.medication_plans.\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
        return try APIResponseDecoder.decodeWrappedData(SparkMedicalSyncAPI.MedicationMutationResponse.self, from: response, decoder: .medicalAPI)
    }

    /// 新建就诊；成功返回记录 ID。
    func createVisit(_ payload: VisitCreatePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/visits/create/", body: payload, decode: IDResponse.self).id
    }

    /// 新建手术；成功返回手术明细与重算后的成员画像摘要。
    func createSurgery(_ payload: SurgeryCreatePayload) async throws -> SparkMedicalSyncAPI.SurgeryMutationResponse {
        try await post(path: "/api/v1/medical/workflows/surgeries/create/", body: payload, decode: SparkMedicalSyncAPI.SurgeryMutationResponse.self)
    }

    /// 更新手术；成功返回手术明细与重算后的成员画像摘要。
    func updateSurgery<B: Encodable & Sendable>(id: Int, body: B) async throws -> SparkMedicalSyncAPI.SurgeryMutationResponse {
        let q = kindQueryItems(.surgeries, extra: [])
        return try await request(
            method: .patch,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: SparkMedicalSyncAPI.SurgeryMutationResponse.self,
            allowETag: false,
            serialKey: "medical.resource.update.surgeries.\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    /// 删除手术；成功返回删除结果与重算后的成员画像摘要。
    func deleteSurgery(id: Int) async throws -> SparkMedicalSyncAPI.SurgeryMutationResponse {
        let q = kindQueryItems(.surgeries, extra: [])
        let response = try await executeRaw(
            method: .delete,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: nil,
            allowETag: false,
            serialKey: "medical.resource.delete.surgeries.\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
        return try APIResponseDecoder.decodeWrappedData(SparkMedicalSyncAPI.SurgeryMutationResponse.self, from: response, decoder: .medicalAPI)
    }

    /// 新建随访；成功返回记录 ID。
    func createFollowUp(_ payload: FollowUpCreatePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/follow-ups/create/", body: payload, decode: IDResponse.self).id
    }

    /// 保存体检报告；成功返回记录 ID。
    func saveHealthExam(_ payload: HealthExamSavePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/health-exams/save/", body: payload, decode: IDResponse.self).id
    }

    /// 保存检查/检验报告（含明细）；成功返回报告记录 ID。
    func saveMedicalReport(_ payload: MedicalReportSavePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/medical-reports/save/", body: payload, decode: IDResponse.self).id
    }

    /// 独立新增检查/检验报告（不创建病例）；成功返回报告记录 ID。
    func createMedicalReport(_ payload: MedicalReportSavePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/medical-reports/create/", body: payload, decode: IDResponse.self).id
    }

    func saveMedicationPlanBundle(_ payload: MedicationPlanBundleSavePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/medication-plans/save/", body: payload, decode: IDResponse.self).id
    }

    func saveMedicationPlanBundleResponse(_ payload: MedicationPlanBundleSavePayload) async throws -> MedicationPlanBundleSaveResponse {
        try await post(
            path: "/api/v1/medical/workflows/medication-plans/save/",
            body: payload,
            decode: MedicationPlanBundleSaveResponse.self
        )
    }

    /// 批量保存处方识别结果（不创建病历，一次提交多条处方及用药计划）。
    func savePrescriptionsBatch(_ payload: PrescriptionBatchSavePayload) async throws -> PrescriptionBatchSaveResponse {
        try await post(
            path: "/api/v1/medical/workflows/prescriptions/batch-save/",
            body: payload,
            decode: PrescriptionBatchSaveResponse.self
        )
    }

    // MARK: - Unified Resource CRUD (`/api/v1/medical/resources/?kind=...`)

    func list<T: Decodable>(
        _ type: [T].Type,
        kind: SparkMedicalResourceKind,
        query: [URLQueryItem] = []
    ) async throws -> [T] {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .get,
            path: Self.resourceCollectionPath,
            queryItems: q,
            body: nil,
            responseType: [T].self,
            allowETag: true,
            serialKey: "medical.resource.list.\(kind.rawValue)",
            queuePriority: .normal,
            isIdempotent: true
        )
    }

    func retrieve<T: Decodable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        id: Int,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .get,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: nil,
            responseType: T.self,
            allowETag: true,
            serialKey: "medical.resource.retrieve.\(kind.rawValue).\(id)",
            queuePriority: .normal,
            isIdempotent: true
        )
    }

    func create<T: Decodable, B: Encodable & Sendable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        body: B,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .post,
            path: Self.resourceCollectionPath,
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: T.self,
            allowETag: false,
            serialKey: "medical.resource.create.\(kind.rawValue)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    func update<T: Decodable, B: Encodable & Sendable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        id: Int,
        body: B,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .patch,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: T.self,
            allowETag: false,
            serialKey: "medical.resource.update.\(kind.rawValue).\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    /// 归档 / 取消归档目标医疗资源（仅提交 `is_archived`，`archived_at` 由服务端写入）。
    nonisolated struct MedicalArchiveUpdatePayload: Encodable, Sendable {
        let isArchived: Bool
    }

    func setArchived<T: Decodable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        id: Int,
        archived: Bool
    ) async throws -> T {
        try await update(
            type,
            kind: kind,
            id: id,
            body: MedicalArchiveUpdatePayload(isArchived: archived)
        )
    }

    func replace<T: Decodable, B: Encodable & Sendable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        id: Int,
        body: B,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .put,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: T.self,
            allowETag: false,
            serialKey: "medical.resource.replace.\(kind.rawValue).\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    func delete(kind: SparkMedicalResourceKind, id: Int, query: [URLQueryItem] = []) async throws {
        let q = kindQueryItems(kind, extra: query)
        let response = try await executeRaw(
            method: .delete,
            path: resourceItemPath(id: id),
            queryItems: q,
            body: nil,
            allowETag: false,
            serialKey: "medical.resource.delete.\(kind.rawValue).\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
        _ = try APIResponseDecoder.decodeWrappedData(JSONValue?.self, from: response, decoder: .medicalAPI)
    }

    /// 统一 POST 封装：JSON  body、高优先级、按 path 维度串行（`serialKey`），禁用 ETag（写操作）。
    ///
    /// - Parameters:
    ///   - path: API 路径（含前导 `/api/...`）。
    ///   - body: 已 `Encodable` 的请求体。
    ///   - decode: 响应 `data` 内层类型的 `Decodable` 类型。
    /// - Returns: 解码后的 `R`。
    private func post<T: Encodable & Sendable, R: Decodable>(path: String, body: T, decode: R.Type) async throws -> R {
        let op = CacheableSparkNetworkOperation(
            name: "Medical.Workflow.\(path)",
            apiName: "MedicalWorkflowAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: path,
                body: .json(AnyEncodable(body)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "medical.workflow.\(path)",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(op)
        return try APIResponseDecoder.decodeWrappedData(R.self, from: response)
    }

    private static let resourceCollectionPath = "/api/v1/medical/resources/"

    private func resourceItemPath(id: Int) -> String {
        "\(Self.resourceCollectionPath)\(id)/"
    }

    private func kindQueryItems(_ kind: SparkMedicalResourceKind, extra: [URLQueryItem]) -> [URLQueryItem] {
        [URLQueryItem(name: "kind", value: kind.rawValue)] + extra
    }

    private func executeRaw(
        method: SparkHTTPMethod,
        path: String,
        queryItems: [URLQueryItem],
        body: SparkBody?,
        allowETag: Bool,
        serialKey: String,
        queuePriority: RequestQueuePriority,
        isIdempotent: Bool
    ) async throws -> SparkNetworkResponse {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Resource.\(method.rawValue).\(path)",
            apiName: "SparkMedicalWorkflowAPI",
            request: SparkNetworkRequest(
                method: method,
                path: path,
                queryItems: queryItems,
                body: body ?? .none,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: allowETag,
                    serialKey: serialKey,
                    retryConfig: .default,
                    isIdempotent: isIdempotent,
                    queuePriority: queuePriority,
                    etagTTL: allowETag ? 120 : nil
                )
            )
        )
        return try await configuration.execute(operation)
    }

    private func request<T: Decodable>(
        method: SparkHTTPMethod,
        path: String,
        queryItems: [URLQueryItem],
        body: SparkBody?,
        responseType: T.Type,
        allowETag: Bool,
        serialKey: String,
        queuePriority: RequestQueuePriority,
        isIdempotent: Bool
    ) async throws -> T {
        let response = try await executeRaw(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body,
            allowETag: allowETag,
            serialKey: serialKey,
            queuePriority: queuePriority,
            isIdempotent: isIdempotent
        )
        return try APIResponseDecoder.decodeWrappedData(responseType, from: response, decoder: .medicalAPI)
    }
}
