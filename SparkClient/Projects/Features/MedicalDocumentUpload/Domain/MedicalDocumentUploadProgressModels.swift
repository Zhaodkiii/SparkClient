import Foundation

// MARK: - 步骤状态

/// 上传识别流程中单个步骤的状态
enum MedicalDocumentUploadStepState: String, Equatable, Sendable {
    case idle       // 等待中
    case running    // 进行中
    case done       // 已完成
    case failed     // 失败
}

// MARK: - 步骤模型

/// 进度列表中的单个步骤
/// 包含标题、副标题、状态和预估时间，用于展示详细的进度信息
struct MedicalDocumentUploadStep: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var subtitle: String?
    var state: MedicalDocumentUploadStepState
    var estimatedSeconds: Int?
    
    static func == (lhs: MedicalDocumentUploadStep, rhs: MedicalDocumentUploadStep) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.state == rhs.state &&
        lhs.estimatedSeconds == rhs.estimatedSeconds
    }
}

// MARK: - 进度模型

/// 上传识别流程的整体进度
/// 包含标题、状态标签、已用时间、预估时间和步骤列表
/// 提供 overallState 计算属性用于判断整体流程状态
struct MedicalDocumentUploadProgress: Identifiable, Equatable, Sendable {
    let id = UUID()
    var title: String
    var statusLabel: String
    var elapsedSeconds: Int
    var estimatedSeconds: Int?
    var steps: [MedicalDocumentUploadStep]
    
    /// 计算整体状态
    /// 优先级：failed > running > done > idle
    var overallState: MedicalDocumentUploadStepState {
        // 优先检查是否有失败的步骤
        if steps.contains(where: { $0.state == .failed }) {
            return .failed
        } else if steps.contains(where: { $0.state == .running }) {
            return .running
        } else if steps.allSatisfy({ $0.state == .done }) {
            return .done
        } else {
            return .idle
        }
    }
    
    static func == (lhs: MedicalDocumentUploadProgress, rhs: MedicalDocumentUploadProgress) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.statusLabel == rhs.statusLabel &&
        lhs.elapsedSeconds == rhs.elapsedSeconds &&
        lhs.estimatedSeconds == rhs.estimatedSeconds &&
        lhs.steps == rhs.steps
    }
}
