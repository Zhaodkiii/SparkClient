import Foundation

// MARK: - 步骤状态

/// 上传识别流程中单个步骤的状态
enum MedicalDocumentUploadStepState: String, Equatable, Sendable {
    case idle       // 等待中
    case running    // 进行中
    case done       // 已完成
    case failed     // 失败
}

enum MedicalDocumentUploadStepDetailKind: String, Equatable, Sendable {
    case ocrFullText
}

// MARK: - 步骤模型
/// 医疗文档上传【单个步骤】模型
/// 描述上传流程中的一个具体执行步骤（如：文件准备、文件上传、服务器校验等）
struct MedicalDocumentUploadStep: Identifiable, Equatable, Sendable {
    /// 步骤唯一标识ID
    let id: String
    
    /// 步骤主标题（展示给用户的步骤名称）
    var title: String
    
    /// 步骤副标题（可选，用于补充说明当前步骤详情）
    var subtitle: String?
    
    /// 当前步骤的执行状态
    var state: MedicalDocumentUploadStepState
    
    /// 预估执行耗时（单位：秒，可选）
    var estimatedSeconds: Int?

    /// 步骤完成后展示在右侧或副区域的短结果摘要。
    var resultSummary: String?

    /// 可点击详情类型，例如 OCR 全文。
    var detailKind: MedicalDocumentUploadStepDetailKind?

    init(
        id: String,
        title: String,
        subtitle: String?,
        state: MedicalDocumentUploadStepState,
        estimatedSeconds: Int?,
        resultSummary: String? = nil,
        detailKind: MedicalDocumentUploadStepDetailKind? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.state = state
        self.estimatedSeconds = estimatedSeconds
        self.resultSummary = resultSummary
        self.detailKind = detailKind
    }
    
    /// Equatable 协议实现：判断两个上传步骤是否相等
    /// 用于视图刷新、状态对比等场景
    static func == (lhs: MedicalDocumentUploadStep, rhs: MedicalDocumentUploadStep) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.state == rhs.state &&
        lhs.estimatedSeconds == rhs.estimatedSeconds &&
        lhs.resultSummary == rhs.resultSummary &&
        lhs.detailKind == rhs.detailKind
    }
}

// MARK: - 进度模型
/// 医疗文档上传进度模型
/// 用于统一管理和展示单个文档上传的整体进度、状态、耗时及分步流程
struct MedicalDocumentUploadProgress: Identifiable, Equatable, Sendable {
    /// 唯一标识（自动生成UUID）
    let id = UUID()
    
    /// 上传标题（如：病历报告、检查单等）
    var title: String
    
    /// 状态文本（展示给用户的状态描述）
    var statusLabel: String
    
    /// 已耗时（秒）
    var elapsedSeconds: Int
    
    /// 预估剩余耗时（秒），可为nil
    var estimatedSeconds: Int?
    
    /// 上传步骤列表（上传流程分多步执行）
    var steps: [MedicalDocumentUploadStep]
    
    /// 计算整体上传状态
    /// 优先级：失败 > 执行中 > 全部完成 > 闲置
    var overallState: MedicalDocumentUploadStepState {
        // 只要有步骤失败，整体状态就是失败（最高优先级）
        if steps.contains(where: { $0.state == .failed }) {
            return .failed
        }
        // 有步骤正在执行，整体状态为执行中
        else if steps.contains(where: { $0.state == .running }) {
            return .running
        }
        // 所有步骤都完成，整体状态为完成
        else if steps.allSatisfy({ $0.state == .done }) {
            return .done
        }
        // 默认闲置状态
        else {
            return .idle
        }
    }
    
    /// Equatable 协议实现：判断两个上传进度是否相等
    /// - Parameters:
    ///   - lhs: 左侧实例
    ///   - rhs: 右侧实例
    /// - Returns: 是否相等
    static func == (lhs: MedicalDocumentUploadProgress, rhs: MedicalDocumentUploadProgress) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.statusLabel == rhs.statusLabel &&
        lhs.elapsedSeconds == rhs.elapsedSeconds &&
        lhs.estimatedSeconds == rhs.estimatedSeconds &&
        lhs.steps == rhs.steps
    }
}
