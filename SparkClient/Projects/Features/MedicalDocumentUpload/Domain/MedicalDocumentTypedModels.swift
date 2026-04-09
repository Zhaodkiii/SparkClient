import Foundation

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
    let memberID: Int                          // 归属于哪位家庭成员
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

/// 病例抽取草稿
struct CaseRecognitionDraft: Sendable, Equatable, Codable {
    let title: String      // 病例标题
    let summary: String    // 病情摘要
    let diagnosis: String? // 诊断结论
    let occurredAt: String?  // 就诊日期
}

/// 医疗报告通用指标项
/// 适用于体检报告和医疗报告（CT、超声等）的指标明细
struct MedicalReportItem: Sendable, Equatable, Codable {
    let category: String       // 科目类别（如：血常规）
    let subCategory: String?   // 子类别
    let itemName: String?       // 项目名称（如：白细胞计数）
    let itemCode: String?      // 项目代码（缩写）
    let resultValue: String    // 结果数值
    let unit: String?          // 单位
    let referenceRange: String? // 参考范围
    let flag: String?          // 异常标记（↑, ↓, H, L, 异常）
    let resultAt: String?        // 采样日期
    let modality: String?      // 检测方法
    let bodyPart: String?      // 检测部位
    let diagnosis: String?     // 医生对该项的诊断
    let extra: [String: String]? // 其他扩展信息
    let sortOrder: Int?        // 排序序号（保持与原件一致）
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
    let reportType: String? // 报告分类
    let title: String       // 报告标题
    let hospital: String?   // 医院名称
    let doctor: String?     // 检查医生
    let content: String     // 报告详情/描述内容
    let date: String?         // 检查日期
    let details: [MedicalReportItem] // 指标明细
}

/// 处方单抽取草稿
struct PrescriptionRecognitionDraft: Sendable, Equatable, Codable {
    /// 药品明细
    struct MedicationItem: Sendable, Equatable, Codable {
        let name: String            // 药品通用名
        let specification: String?   // 规格（如：20mg * 12片）
        let dosage: String?          // 单次剂量（如：1片/次）
        let frequency: String?       // 频次（如：3次/日）
        let duration: String?        // 疗程（如：7天）
        let instructions: String?    // 用法备注（如：餐后服用）
    }

    let prescriberName: String?     // 开方医生
    let institutionName: String?    // 开方医院
    let prescribedAt: String?         // 开方日期
    let diagnosis: String?          // 临床诊断
    let batchNo: String?            // 处方编号
    let medications: [MedicationItem] // 药品明细列表
}

/// 单一药品/用药提醒抽取草稿
struct MedicationRecognitionDraft: Sendable, Equatable, Codable {
    let drugName: String       // 药品名称
    let dosage: String?        // 剂量
    let frequencyText: String? // 频率描述
    let durationDays: Int?     // 预计服用天数
    let instructions: String?  // 使用说明
}

// MARK: - 最终输出封装

/// 类型化的识别结果：使用枚举关联值将不同的草稿模型归一化。
/// 这种设计允许 UI 层通过 switch 语句，根据文档类型路由到不同的结果展示页面。
enum MedicalDocumentTypedResult: Sendable, Equatable {
    case caseDocument(CaseRecognitionDraft)
    case healthExamReport(HealthExamRecognitionDraft)
    case medicalReport([MedicalReportRecognitionDraft])
    case prescription(PrescriptionRecognitionDraft)
    case medication(MedicationRecognitionDraft)
}

/// 最终输出模型：抽取流程的最终产物。
/// 包含所有上下文信息及结构化后的结果，直接供“结果确认页”渲染使用。
struct MedicalDocumentTypedExtractionOutput: Sendable, Equatable {
    let envelope: MedicalDocumentRecognitionEnvelope // 识别过程的全量上下文
    let typedResult: MedicalDocumentTypedResult       // 具体的类型化结构数据
    let extractedJSON: String                         // 成功提取后的 JSON 字符串
    let payloadPreview: String                        // 用于展示给用户的 JSON 预览（调试/确认用）
}
