import Foundation

/// 表示待上传的本地医疗文件模型
/// 遵循 Identifiable 方便在 SwiftUI 列表中使用
/// 遵循 Sendable 确保跨并发任务传输时的安全性
struct MedicalUploadLocalFile: Identifiable, Equatable, Sendable {
    let id: UUID             // 唯一标识符，默认为随机 UUID
    let url: URL             // 文件在设备沙盒或系统选择器中的本地路径
    let displayName: String   // 用于在界面上显示的文件名
    let mimeType: String?    // 文件的媒体类型（如 "image/jpeg", "application/pdf"）
    let ocrText: String?     // 单文件 OCR 识别结果
    let remoteFile: ManagedFileRecord? // 上传成功后的远端文件记录

    init(
        id: UUID = UUID(),
        url: URL,
        displayName: String,
        mimeType: String? = nil,
        ocrText: String? = nil,
        remoteFile: ManagedFileRecord? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.mimeType = mimeType
        self.ocrText = ocrText
        self.remoteFile = remoteFile
    }

    func withOCRText(_ text: String?) -> MedicalUploadLocalFile {
        MedicalUploadLocalFile(
            id: id,
            url: url,
            displayName: displayName,
            mimeType: mimeType,
            ocrText: text,
            remoteFile: remoteFile
        )
    }

    func withRemoteFile(_ file: ManagedFileRecord?) -> MedicalUploadLocalFile {
        MedicalUploadLocalFile(
            id: id,
            url: url,
            displayName: displayName,
            mimeType: mimeType,
            ocrText: ocrText,
            remoteFile: file
        )
    }
}

/// 医疗文档的上传/处理模式
/// 用于告诉后端或 OCR 引擎按何种逻辑解析文档
enum MedicalDocumentUploadMode: String, Codable, CaseIterable, Sendable {
    case general      // 通用模式：无特定分类
    case medicalCase  // 病历模式：侧重于病史、诊断等
    case healthExam   // 体检报告模式：侧重于各项生理指标
    case medicalExam  // 医学检查模式：如 CT、核磁共振报告
    case medication   // 用药记录模式：侧重于处方和药物清单
}

/// 医疗文档 OCR 识别结果模型
/// 承载从服务器识别出的文本及结构化数据
struct MedicalDocumentRecognitionResult: Sendable, Equatable {
    let memberID: Int                           // 归属成员的 ID
    let requestedMode: MedicalDocumentUploadMode? // 用户上传时请求的模式
    let resolvedMode: MedicalDocumentUploadMode?  // 后端 AI 最终判定/修正后的模式
    let rawOCRText: String                      // OCR 扫描出的原始全文本
    let extractedJSONString: String             // 经过结构化处理后的 JSON 字符串（包含关键字段）
    let extractedSummary: String?               // AI 生成的内容摘要
    let serverPayloadPreview: String?           // 提交给服务器保存前的预览数据（调试用）
}

/// 医疗文档保存后的回执模型
/// 当识别结果确认并正式保存到数据库后返回
struct MedicalDocumentSaveReceipt: Sendable, Equatable {
    let recordID: Int    // 数据库中生成的记录唯一 ID
    let savedAt: Date    // 最终保存成功的时间戳
    let isSuccess: Bool  // 是否保存成功
}
