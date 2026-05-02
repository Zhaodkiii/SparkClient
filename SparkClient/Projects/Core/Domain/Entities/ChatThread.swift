import Foundation

/// 聊天会话模型
/// 对应一个独立的对话窗口/会话，存储会话配置、AI参数、状态等所有信息
struct ChatThread: Identifiable, Codable, Equatable, Sendable {
    
    // MARK: - 基础属性
    /// 会话唯一ID
    let id: UUID
    /// 关联的成员ID（可选）
    let memberID: Int?
    /// 会话标题
    let title: String
    /// 会话场景（聊天 / 助手 等）
    let scenario: AIScenario
    
    // MARK: - AI 模型参数
    /// 当前使用的模型名称
    let currentModelName: String?
    /// 温度系数（控制生成随机性，0~1）
    let temperature: Double
    /// 核采样参数（控制生成多样性）
    let topP: Double
    /// 最大生成Token数
    let maxTokens: Int
    /// 最大上下文消息数
    let maxMessages: Int
    /// 角色提示词（系统Prompt）
    let rolePrompt: String
    
    // MARK: - 图片发送模式
    /// 图片传输模式原始值（用于持久化存储）
    /// nil 表示旧版本数据，产品默认按【直发多模态】处理
    let imageDeliveryModeRaw: String?
    
    // MARK: - 状态与时间
    /// 是否已删除
    let isDeleted: Bool
    /// 删除时间
    let deletedAt: Date?
    /// 创建时间
    let createdAt: Date
    /// 更新时间
    let updatedAt: Date
    /// 服务器端更新时间（用于同步）
    let serverUpdatedAt: Date?
    
    // MARK: - 计算属性
    
    /// 图片发送模式（与ZDK兼容）
    /// 自动解析原始值，缺失或无效时默认返回 `.directMultimodal`
    var imageDeliveryMode: ChatThreadImageDeliveryMode {
        // 过滤空字符串和空白字符
        guard let raw = imageDeliveryModeRaw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return .directMultimodal
        }
        
        // 优先使用枚举原始值解析
        if let mode = ChatThreadImageDeliveryMode(rawValue: raw) {
            return mode
        }
        
        // 兼容旧版字符串格式
        switch raw {
        case "direct_multimodal":
            return .directMultimodal
        case "local_ocr":
            return .localOCR
        default:
            // 未知类型默认使用直发多模态
            return .directMultimodal
        }
    }
    
    // MARK: - 初始化方法
    
    /// 非孤立初始化方法（支持并发环境安全调用）
    nonisolated init(
        id: UUID = UUID(),
        memberID: Int? = nil,
        title: String,
        scenario: AIScenario = .chat,
        currentModelName: String? = nil,
        temperature: Double = 0.6,
        topP: Double = 1.0,
        maxTokens: Int = 4096,
        maxMessages: Int = 20,
        rolePrompt: String = "",
        imageDeliveryModeRaw: String? = nil,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        serverUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.memberID = memberID
        self.title = title
        self.scenario = scenario
        self.currentModelName = currentModelName
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        // 确保最大消息数至少为1，防止无效值
        self.maxMessages = max(maxMessages, 1)
        self.rolePrompt = rolePrompt
        self.imageDeliveryModeRaw = imageDeliveryModeRaw
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverUpdatedAt = serverUpdatedAt
    }
}
