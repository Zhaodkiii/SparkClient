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
    struct CaseSavePayload: Encodable, Sendable {
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

        enum CodingKeys: String, CodingKey {
            case member
            case recordType = "record_type"
            case status
            case title
            case hospitalName = "hospital_name"
            case ageAtVisit = "age_at_visit"
            case diagnosisSummary = "diagnosis_summary"
            case extra
        }
    }

    /// 体检报告保存请求体。
    struct HealthExamSavePayload: Encodable, Sendable {
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

        enum CodingKeys: String, CodingKey {
            case member
            case institutionName = "institution_name"
            case reportNo = "report_no"
            case examDate = "exam_date"
            case examType = "exam_type"
            case summary
            case source
            case rawOCR = "raw_ocr"
            case status
            case extra
            case details
        }
    }

    /// 检查/检验报告中的「明细行」：单项结果（如血常规某一指标、影像所见子项等）。
    struct MedicalReportDetailPayload: Encodable, Sendable {
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
            case extra
            case sortOrder = "sort_order"
        }
    }

    /// 检查/检验报告主记录保存请求体（含多条 `details`）。
    struct MedicalReportSavePayload: Encodable, Sendable {
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

        enum CodingKeys: String, CodingKey {
            case member
            case medicalCase = "medical_case"
            case category
            case subCategory = "sub_category"
            case itemName = "item_name"
            case performedAt = "performed_at"
            case reportedAt = "reported_at"
            case organizationName = "organization_name"
            case departmentName = "department_name"
            case doctorName = "doctor_name"
            case findings
            case impression
            case modality
            case bodyPart = "body_part"
            case diagnosis
            case fileIds = "file_ids"
            case details
        }
    }

    /// 症状新建请求体（表单创建专用）。
    struct SymptomCreatePayload: Encodable, Sendable {
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

        enum CodingKeys: String, CodingKey {
            case member
            case medicalCase = "medical_case"
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

    /// 就诊新建请求体（表单创建专用）。
    struct VisitCreatePayload: Encodable, Sendable {
        let member: Int
        let medicalCase: Int?
        let visitType: String?
        let visitedAt: String?
        let department: String?
        let doctorName: String?
        let visitNo: String?
        let notes: String?

        enum CodingKeys: String, CodingKey {
            case member
            case medicalCase = "medical_case"
            case visitType = "visit_type"
            case visitedAt = "visited_at"
            case department
            case doctorName = "doctor_name"
            case visitNo = "visit_no"
            case notes
        }
    }

    /// 手术新建请求体（表单创建专用）。
    struct SurgeryCreatePayload: Encodable, Sendable {
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

        enum CodingKeys: String, CodingKey {
            case member
            case medicalCase = "medical_case"
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

    /// 随访新建请求体（表单创建专用）。
    struct FollowUpCreatePayload: Encodable, Sendable {
        let member: Int
        let medicalCase: Int?
        let plannedAt: String?
        let completedAt: String?
        let status: String?
        let method: String?
        let outcome: String?
        let nextAction: String?

        enum CodingKeys: String, CodingKey {
            case member
            case medicalCase = "medical_case"
            case plannedAt = "planned_at"
            case completedAt = "completed_at"
            case status
            case method
            case outcome
            case nextAction = "next_action"
        }
    }

    /// 处方批次保存请求体：一次保存包含处方头信息与多条药品行。
    ///
    /// 服务端返回的是「批次」对象 ID（见 `savePrescription`），药品可再单独 `saveMedication` 并引用 `batch`。
    struct PrescriptionSavePayload: Encodable, Sendable {
        /// 关联成员 ID。
        let member: Int
        /// 关联病历 ID；无则 `nil`。
        let medicalCase: Int?
        /// 开方医师姓名。
        let prescriberName: String
        /// 开方机构/医院名称。
        let institutionName: String
        /// 开方时间。
        let prescribedAt: String?
        /// 临床诊断文本。
        let diagnosis: String
        /// 批次号（业务展示或对接用）。
        let batchNo: String
        /// 处方状态；`nil` 时不编码该字段，由服务端默认（一般为 `active`）。
        let status: String?
        /// 审核人姓名。
        let auditorName: String
        /// 审核时间；未审核可 `nil`。
        let auditedAt: String?
        /// 扩展字段。
        let extra: [String: String]
        /// 本批次内药品行；可与后续单条 `MedicationSavePayload` 配合使用。
        let medications: [MedicationSavePayload]

        enum CodingKeys: String, CodingKey {
            case member
            case medicalCase = "medical_case"
            case prescriberName = "prescriber_name"
            case institutionName = "institution_name"
            case prescribedAt = "prescribed_at"
            case diagnosis
            case batchNo = "batch_no"
            case status
            case auditorName = "auditor_name"
            case auditedAt = "audited_at"
            case extra
            case medications
        }
    }

    /// 单条药品保存请求体；通常需关联已存在的处方批次 ID（`batch`）。
    struct MedicationSavePayload: Encodable, Sendable {
        /// 关联成员 ID。
        let member: Int
        /// 处方批次服务端 ID（`Prescription` batch）。
        let batch: Int
        /// 通用名。
        let genericName: String
        /// 商品名。
        let brandName: String
        /// 展示用合成药名（若与通用名/商品名重复可遵循产品规则）。
        let drugName: String
        /// 剂型（片剂、胶囊等）。
        let dosageForm: String
        /// 规格强度描述（如「500mg」）。
        let strength: String
        /// 给药途径（口服、静脉等）。
        let route: String
        /// 每次剂量展示文案（与 `doseValue`/`doseUnit` 可同时存在）。
        let dosePerTime: String
        /// 每次剂量数值；无法解析时为 `nil`。
        let doseValue: Double?
        /// 剂量单位。
        let doseUnit: String
        /// 频次编码（如 BID），与后端字典一致。
        let frequencyCode: String
        /// 周期描述（如「每日」「每周」的编码或文本，以后端为准）。
        let period: String
        /// 每周期次数；可选。
        let timesPerPeriod: Int?
        /// 频次完整可读文案（兜底展示）。
        let frequencyText: String
        /// 用药天数；可选。
        let durationDays: Int?
        /// 用法用量说明/医嘱。
        let instructions: String
        /// 是否启用服药提醒。
        let reminderEnabled: Bool
        /// 提醒时间点列表（通常为时间字符串数组）。
        let reminderTimes: [String]
        /// 排序序号。
        let sortOrder: Int
        /// 扩展字段。
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case member, batch, strength, route, period, instructions, extra
            case genericName = "generic_name"
            case brandName = "brand_name"
            case drugName = "drug_name"
            case dosageForm = "dosage_form"
            case dosePerTime = "dose_per_time"
            case doseValue = "dose_value"
            case doseUnit = "dose_unit"
            case frequencyCode = "frequency_code"
            case timesPerPeriod = "times_per_period"
            case frequencyText = "frequency_text"
            case durationDays = "duration_days"
            case reminderEnabled = "reminder_enabled"
            case reminderTimes = "reminder_times"
            case sortOrder = "sort_order"
        }
    }

    /// 用药工作流「批量」请求体：顶层 `member` 与首条内 `member` 二选一（服务端以首条为准，缺省用顶层）。
    /// 行内不含 `member` / `batch`，由服务端创建占位批次后写入。
    struct MedicationWorkflowBulkPayload: Encodable, Sendable {
        let member: Int
        let fileIds: [Int]
        let medications: [MedicationWorkflowBulkLinePayload]

        enum CodingKeys: String, CodingKey {
            case member
            case fileIds = "file_ids"
            case medications
        }
    }

    /// 批量用药行（字段与 ``MedicationSavePayload`` 一致，但不包含 `member` / `batch`）。
    struct MedicationWorkflowBulkLinePayload: Encodable, Sendable {
        let genericName: String
        let brandName: String
        let drugName: String
        let dosageForm: String
        let strength: String
        let route: String
        let dosePerTime: String
        let doseValue: Double?
        let doseUnit: String
        let frequencyCode: String
        let period: String
        let timesPerPeriod: Int?
        let frequencyText: String
        let durationDays: Int?
        let instructions: String
        let reminderEnabled: Bool
        let reminderTimes: [String]
        let sortOrder: Int
        let extra: [String: String]

        enum CodingKeys: String, CodingKey {
            case strength, route, period, instructions, extra
            case genericName = "generic_name"
            case brandName = "brand_name"
            case drugName = "drug_name"
            case dosageForm = "dosage_form"
            case dosePerTime = "dose_per_time"
            case doseValue = "dose_value"
            case doseUnit = "dose_unit"
            case frequencyCode = "frequency_code"
            case timesPerPeriod = "times_per_period"
            case frequencyText = "frequency_text"
            case durationDays = "duration_days"
            case reminderEnabled = "reminder_enabled"
            case reminderTimes = "reminder_times"
            case sortOrder = "sort_order"
        }

        init(strippingMemberAndBatchFrom row: MedicationSavePayload) {
            genericName = row.genericName
            brandName = row.brandName
            drugName = row.drugName
            dosageForm = row.dosageForm
            strength = row.strength
            route = row.route
            dosePerTime = row.dosePerTime
            doseValue = row.doseValue
            doseUnit = row.doseUnit
            frequencyCode = row.frequencyCode
            period = row.period
            timesPerPeriod = row.timesPerPeriod
            frequencyText = row.frequencyText
            durationDays = row.durationDays
            instructions = row.instructions
            reminderEnabled = row.reminderEnabled
            reminderTimes = row.reminderTimes
            sortOrder = row.sortOrder
            extra = row.extra
        }
    }

    /// 通用「仅返回 id」的响应解码结构。
    private struct IDResponse: Decodable { let id: Int }

    /// 处方保存接口返回嵌套结构：`{ batch: { id: ... } }`，此处解出批次 ID。
    private struct PrescriptionResponse: Decodable {
        let batch: IDResponse
    }

    /// 保存病历类文档；成功返回新建或更新后的记录 ID。
    func saveCase(_ payload: CaseSavePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/case-documents/save/", body: payload, decode: IDResponse.self).id
    }

    /// 新建症状；成功返回记录 ID。
    func createSymptom(_ payload: SymptomCreatePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/symptoms/create/", body: payload, decode: IDResponse.self).id
    }

    /// 新建就诊；成功返回记录 ID。
    func createVisit(_ payload: VisitCreatePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/visits/create/", body: payload, decode: IDResponse.self).id
    }

    /// 新建手术；成功返回记录 ID。
    func createSurgery(_ payload: SurgeryCreatePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/surgeries/create/", body: payload, decode: IDResponse.self).id
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

    /// 保存处方批次；成功返回**处方批次** ID（非单药品 ID）。
    func savePrescription(_ payload: PrescriptionSavePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/prescriptions/save/", body: payload, decode: PrescriptionResponse.self).batch.id
    }

    /// 保存单条药品记录；成功返回药品行 ID（兼容旧客户端）。
    func saveMedication(_ payload: MedicationSavePayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/medications/save/", body: payload, decode: IDResponse.self).id
    }

    /// 批量保存用药记录（一次请求多条）；成功返回**第一条**药品行 ID（`data.id`）。
    func saveMedicationsWorkflow(_ payload: MedicationWorkflowBulkPayload) async throws -> Int {
        try await post(path: "/api/v1/medical/workflows/medications/save/", body: payload, decode: IDResponse.self).id
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

    func create<T: Decodable, B: Encodable>(
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

    func update<T: Decodable, B: Encodable>(
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

    func replace<T: Decodable, B: Encodable>(
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
        _ = try APIResponseDecoder.decodeWrappedData(JSONValue?.self, from: response, decoder: .sparkMedicalResource)
    }

    /// 统一 POST 封装：JSON  body、高优先级、按 path 维度串行（`serialKey`），禁用 ETag（写操作）。
    ///
    /// - Parameters:
    ///   - path: API 路径（含前导 `/api/...`）。
    ///   - body: 已 `Encodable` 的请求体。
    ///   - decode: 响应 `data` 内层类型的 `Decodable` 类型。
    /// - Returns: 解码后的 `R`。
    private func post<T: Encodable, R: Decodable>(path: String, body: T, decode: R.Type) async throws -> R {
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
        return try APIResponseDecoder.decodeWrappedData(responseType, from: response, decoder: .sparkMedicalResource)
    }
}

private extension JSONDecoder {
    static let sparkMedicalResource: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(MedicalDateCoding.decodeFlexibleDate(from:))
        return decoder
    }()
}
