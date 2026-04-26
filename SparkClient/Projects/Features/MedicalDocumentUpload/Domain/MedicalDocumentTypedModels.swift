import Foundation

// MARK: - 流式 JSON 兼容：标量可为 String / Int / Double，统一为 String?

/// LLM 流式输出常把 `sortOrder` 等字段写成数字；模型层仍用 `String?` 承接脏数据。
@propertyWrapper
struct FlexibleOptionalString: Codable, Sendable, Equatable, Hashable {
    var wrappedValue: String?

    init(wrappedValue: String?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if try container.decodeNil() {
            wrappedValue = nil
            return
        }
        if let stringValue = try? container.decode(String.self) {
            wrappedValue = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            wrappedValue = String(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            wrappedValue = String(doubleValue)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "无法将该字段转换为 String")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch wrappedValue {
        case .none:
            try container.encodeNil()
        case .some(let value):
            try container.encode(value)
        }
    }
}

extension KeyedDecodingContainer {
    /// 让 `@FlexibleOptionalString` 在键缺失时自动回落为 nil，避免触发 keyNotFound。
    func decode(_ type: FlexibleOptionalString.Type, forKey key: Key) throws -> FlexibleOptionalString {
        try decodeIfPresent(type, forKey: key) ?? FlexibleOptionalString(wrappedValue: nil)
    }
}

// MARK: - 基础枚举与配置

/// 报告类型：定义了系统能够处理的所有医疗文档范畴。
/// 支持 CaseIterable 以便在 UI 选择器中直接遍历，Sendable 保证并发安全。
enum MedicalDocumentKind: String, Codable, CaseIterable, Sendable {
    case auto             // 自动识别（由系统 AI 判定）
    case caseDocument     // 病例文档（出院小结、门诊病历等）
    case healthExamReport // 体检报告（包含大量数值指标）
    case medicalReport    // 医疗报告（如 B超、CT、放射科报告）
    case prescription     // 处方单（用药清单与剂量）
    case medication       // 药品说明/包装（侧重于单一药品信息）
}

/// 报告类型识别结果：记录系统是如何判定文档类型的。
struct MedicalDocumentTypeResolution: Sendable, Equatable, Codable {
    /// 识别来源：记录分类决策是由谁做出的。
    enum Source: String, Codable, Sendable {
        case manual     // 用户手动指定
        case localRules // 本地正则表达式或关键词规则判定
        case ai         // 大模型 (LLM) 语义判定
    }

    let kind: MedicalDocumentKind // 判定的类型
    let confidence: Double        // 置信度（0.0 ~ 1.0）
    let source: Source            // 决策来源
    let reason: String?           // 判定理由（例如：命中关键词“出院记录”）
}

// MARK: - 流程上下文

/// 识别上下文壳：作为整个上传解析链路的“集装箱”。
/// 它携带了从原始文件到 OCR 文本，再到类型判定的所有中间产物。
/// 注：不含 `Codable`（`MedicalUploadLocalFile` / `ManagedFileRecord` 非 JSON 持久化模型）。
struct MedicalDocumentRecognitionEnvelope: Sendable, Equatable {
    let memberID: Int?                         // 归属于哪位家庭成员；对话抽取场景可先为空，保存时再绑定。
    let sourceFiles: [MedicalUploadLocalFile]   // 原始本地文件引用
    let rawOCRText: String                      // OCR 识别出的全部原始文本
    let typeResolution: MedicalDocumentTypeResolution // 类型判定结论
}

/// 文件映射：将本地选择的文件对象与服务端生成的持久化记录进行绑定。
struct UploadedMedicalDocumentFile: Sendable, Equatable {
    let localFile: MedicalUploadLocalFile // 本地临时文件
    let remoteFile: ManagedFileRecord     // 服务端数据库记录（包含文件 ID、URL 等）
}

// MARK: - 结构化数据草稿 (Drafts)

/// 医疗报告通用指标项
/// 适用于体检报告和医疗报告（CT、超声等）的指标明细
struct MedicalReportItem: Sendable, Equatable, Codable {
    let category: String       // 科目类别（如：血常规）
    let subCategory: String?   // 子类别
    let itemName: String?       // 项目名称（如：白细胞计数）
    let itemCode: String?      // 项目代码（缩写）
    let resultValue: String?    // 结果数值
    let unit: String?          // 单位
    let referenceRange: String? // 参考范围
    let flag: String?          // 异常标记（↑, ↓, H, L, 异常）
    let resultAt: String?        // 采样日期
    let modality: String?      // 检测方法
    let bodyPart: String?      // 检测部位
    let diagnosis: String?     // 医生对该项的诊断
    let extra: [String: String]? // 其他扩展信息
    /// 排序序号（保持与原件一致）；流式 JSON 常为字符串 `"4"`，亦可能为数字
    @FlexibleOptionalString var sortOrder: String?

}

/// 体检报告抽取草稿
struct HealthExamRecognitionDraft: Sendable, Equatable, Codable {
    let institutionName: String? // 体检机构名称
    let reportNo: String?        // 报告单号
    let examDate: String?          // 体检日期
    let examType: String?        // 体检类型
    let summary: String?         // 体检综述/建议
    let items: [MedicalReportItem] // 指标明细列表
}

/// 医疗报告抽取草稿（适用于 CT、超声等影像学报告）
struct MedicalReportRecognitionDraft: Sendable, Equatable, Codable {
    let category: String? // 报告分类
    let title: String       // 报告标题
    let hospital: String?   // 医院名称
    let doctor: String?     // 检查医生
    let content: String     // 报告详情/描述内容
    let date: String?         // 检查日期
    let details: [MedicalReportItem] // 指标明细
}

// MARK: - 用药：与 `Medication` ORM 对齐的抽取行（处方明细与单一药品文档共用）

/// 与 ``Medication`` 字段一一对应；流式 JSON 解码依赖 `JSONDecoder.keyDecodingStrategy == .convertFromSnakeCase`。
/// 注意：数值字段使用 String? 以兼容 OCR 脏数据，后续通过扩展方法转换为实际数值。
struct MedicationRecognitionDraft: Sendable, Equatable, Codable {
    let genericName: String?
    let brandName: String?
    let drugName: String?
    let dosageForm: String?
    let strength: String?
    let route: String?
    let dosePerTime: String?
    let doseValue: String?          // OCR 原始字符串，如 "1", "0.5", "1g"
    let doseUnit: String?
    let frequencyCode: String?
    let period: String?
    let timesPerPeriod: String?     // OCR 原始字符串，如 "2", "3次", "每日2次"
    let frequencyText: String?
    let durationDays: String?       // OCR 原始字符串，如 "7", "7天"
    let instructions: String?
    let reminderEnabled: Bool?
    let reminderTimes: [String]?
    /// 批次内排序；流式 JSON 常为字符串
    @FlexibleOptionalString var sortOrder: String?
    let extra: [String: String]?

}

/// 处方批次抽取草稿（与 ``PrescriptionBatch`` / ``PrescriptionBatchSerializer`` 字段对齐；`member` 由上传信封提供）。
struct PrescriptionRecognitionDraft: Sendable, Equatable, Codable {
    /// 关联病历 ID：由 App 在保存/编辑已有病例时注入；**不从** OCR 流式 JSON 解码（避免模型输出字符串与 `Int` 不一致）。
    let medicalCase: Int?
    let prescriberName: String?
    let institutionName: String?
    let prescribedAt: String?
    let diagnosis: String?
    let batchNo: String?
    let status: String?
    let auditorName: String?
    let auditedAt: String?
    let extra: [String: String]?
    /// 批次内药品行；缺省或省略时按空数组处理。
    let medications: [MedicationRecognitionDraft]?

}

// MARK: - 新增 Draft 模型（症状/就诊/手术/随访）

/// 症状抽取草稿（与 ``Symptom`` 字段语义对齐）。
/// 参考 SparkService 的 Symptom 模型和 HealthClient 的 SymptomDraft
struct SymptomRecognitionDraft: Sendable, Equatable, Codable {
    let name: String              // 症状名称
    let code: String?             // 症状编码
    let severity: String?         // 严重程度
    let startedAt: String?        // 开始时间 (ISO 日期字符串)
    let durationValue: String?       // 持续时间数值
    let durationUnit: String?     // 持续时间单位 (天/周/月等)
    let bodyPart: String?         // 身体部位
    let notes: String?            // 备注说明
}

/// 就诊信息抽取草稿（与 ``Visit`` 字段语义对齐）。
/// 参考 SparkService 的 Visit 模型
struct VisitRecognitionDraft: Sendable, Equatable, Codable {
    let visitType: String?        // 就诊类型 (门诊/急诊/随诊等)
    let visitedAt: String?        // 就诊时间 (ISO 日期字符串)
    let department: String?       // 就诊科室
    let doctorName: String?       // 医生姓名
    let visitNo: String?          // 就诊号/病历号
    let notes: String?            // 备注
}

/// 手术信息抽取草稿（与 ``Surgery`` 字段语义对齐）。
/// 参考 SparkService 的 Surgery 模型
struct SurgeryRecognitionDraft: Sendable, Equatable, Codable {
    let procedureName: String     // 手术名称
    let procedureCode: String?    // 手术编码
    let site: String?             // 手术部位
    let performedAt: String?      // 手术时间 (ISO 日期字符串)
    let surgeon: String?          // 主刀医生
    let anesthesiaType: String?   // 麻醉方式
    let incisionLevel: String?    // 切口等级
    let asaClass: String?         // ASA 分级
    let notes: String?            // 备注
}

/// 随访信息抽取草稿（与 ``FollowUp`` 字段语义对齐）。
/// 参考 SparkService 的 FollowUp 模型
struct FollowUpRecognitionDraft: Sendable, Equatable, Codable {
    let plannedAt: String?        // 计划随访时间 (ISO 日期字符串)
    let completedAt: String?      // 实际完成时间 (ISO 日期字符串)
    let status: String?           // 随访状态
    let method: String?           // 随访方式
    let outcome: String?          // 随访结果
    let nextAction: String?       // 下一步行动建议
}

/// 病例抽取草稿（汇总结构，与 `RecognizedMedical` 语义对齐）。
/// 主档字段与 `MedicalCase` 摘要对齐；子项可选，供组合创建 API 一次性落库。
struct CaseRecognitionDraft: Sendable, Equatable, Codable {
    let title: String // 病例标题 → `title`
    let summary: String? // 病情摘要 → 并入 `diagnosis_summary`
    let diagnosis: String? // 诊断结论 → 并入 `diagnosis_summary`
    let hospitalName: String? // 医院名称 → `hospital_name`
    let ageAtVisit: String? // 就诊年龄 → `age_at_visit`
    /// 就诊日期（原始字符串，如 ISO 日期）；主档无列时写入保存 `extra["occurred_at"]`。
    let occurredAt: String?

    /// 子项：症状（单条；与组合创建 API `symptom` 对齐）
    let symptom: SymptomRecognitionDraft?
    /// 子项：就诊（单条；与组合创建 API `visit` 对齐）
    let visit: VisitRecognitionDraft?
    /// 子项：手术（单条；与组合创建 API `surgery` 对齐）
    let surgery: SurgeryRecognitionDraft?
    /// 子项：随访
    let followUps: [FollowUpRecognitionDraft]?
    /// 子项：处方批次（含批次内药品行）
    let prescriptionBatches: [PrescriptionRecognitionDraft]?
    /// 子项：检查/检验报告（与独立「医疗报告」类型共用草稿模型）
    let examinationReports: [MedicalReportRecognitionDraft]?
}

// MARK: - 最终输出封装

/// 类型化的识别结果：使用枚举关联值将不同的草稿模型归一化。
/// 这种设计允许 UI 层通过 switch 语句，根据文档类型路由到不同的结果展示页面。
enum MedicalDocumentTypedResult: Sendable, Equatable {
    /// 病例文档（汇总草稿，内含症状/就诊/手术/随访/处方/检查报告等子项）
    case caseDocument(CaseRecognitionDraft)
    case healthExamReport(HealthExamRecognitionDraft)
    case medicalReport([MedicalReportRecognitionDraft])
    case prescription(PrescriptionRecognitionDraft)
    case medication([MedicationRecognitionDraft])
}

/// 最终输出模型：抽取流程的最终产物。
/// 包含所有上下文信息及结构化后的结果，直接供“结果确认页”渲染使用。
struct MedicalDocumentTypedExtractionOutput: Sendable, Equatable {
    let envelope: MedicalDocumentRecognitionEnvelope // 识别过程的全量上下文
    let typedResult: MedicalDocumentTypedResult       // 具体的类型化结构数据
    let extractedJSON: String                         // 成功提取后的 JSON 字符串
    let payloadPreview: String                        // 用于展示给用户的 JSON 预览（调试/确认用）
}
