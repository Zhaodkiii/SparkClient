import Foundation

/// 报告类型选择：支持自动识别与手动指定业务类型。
enum MedicalDocumentKind: String, Codable, CaseIterable, Sendable {
    case auto
    case caseDocument
    case healthExamReport
    case medicalReport
    case prescription
    case medication
}

/// 报告类型识别结果（规则/AI 两阶段共用）。
struct MedicalDocumentTypeResolution: Sendable, Equatable {
    enum Source: String, Codable, Sendable {
        case manual
        case localRules
        case ai
    }

    let kind: MedicalDocumentKind
    let confidence: Double
    let source: Source
    let reason: String?
}

/// 识别上下文壳：保留原始 OCR 与类型判定，供后续抽取/保存共用。
struct MedicalDocumentRecognitionEnvelope: Sendable, Equatable {
    let memberID: Int
    let sourceFiles: [MedicalUploadLocalFile]
    let rawOCRText: String
    let typeResolution: MedicalDocumentTypeResolution
}

/// 上传后的源文件映射（本地文件 + 服务端文件记录）。
struct UploadedMedicalDocumentFile: Sendable, Equatable {
    let localFile: MedicalUploadLocalFile
    let remoteFile: ManagedFileRecord
}

/// 病例抽取草稿。
struct CaseRecognitionDraft: Sendable, Equatable {
    let title: String
    let summary: String
    let diagnosis: String?
    let occurredAt: Date?
    let rawJSON: String
}

/// 体检报告抽取草稿。
struct HealthExamRecognitionDraft: Sendable, Equatable {
    struct Item: Sendable, Equatable {
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
        let diagnosis: String?
        let extra: [String: String]
        let sortOrder: Int
    }

    let institutionName: String?
    let reportNo: String?
    let examDate: Date?
    let examType: String?
    let summary: String?
    let items: [Item]
    let rawJSON: String
}

/// 医疗报告抽取草稿。
struct MedicalReportRecognitionDraft: Sendable, Equatable {
    struct DetailItem: Sendable, Equatable {
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
        let diagnosis: String?
        let extra: [String: String]
        let sortOrder: Int
    }

    let reportType: String?
    let title: String
    let hospital: String?
    let doctor: String?
    let content: String
    let date: Date?
    let details: [DetailItem]
    let rawJSON: String
}

/// 处方抽取草稿。
struct PrescriptionRecognitionDraft: Sendable, Equatable {
    struct MedicationItem: Sendable, Equatable {
        let name: String
        let specification: String?
        let dosage: String?
        let frequency: String?
        let duration: String?
        let instructions: String?
    }

    let prescriberName: String?
    let institutionName: String?
    let prescribedAt: Date?
    let diagnosis: String?
    let batchNo: String?
    let medications: [MedicationItem]
    let rawJSON: String
}

/// 用药抽取草稿。
struct MedicationRecognitionDraft: Sendable, Equatable {
    let drugName: String
    let dosage: String?
    let frequencyText: String?
    let durationDays: Int?
    let instructions: String?
    let rawJSON: String
}

/// 顶层 typed 抽取结果，驱动结果页路由与保存分发。
enum MedicalDocumentTypedResult: Sendable, Equatable {
    case caseDocument(CaseRecognitionDraft)
    case healthExamReport(HealthExamRecognitionDraft)
    case medicalReport(MedicalReportRecognitionDraft)
    case prescription(PrescriptionRecognitionDraft)
    case medication(MedicationRecognitionDraft)
}

/// typed 抽取输出：供结果页展示与保存链路使用。
struct MedicalDocumentTypedExtractionOutput: Sendable, Equatable {
    let envelope: MedicalDocumentRecognitionEnvelope
    let typedResult: MedicalDocumentTypedResult
    let extractedJSON: String
    let payloadPreview: String
}
