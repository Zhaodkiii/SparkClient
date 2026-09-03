import Foundation

/// CHAT-000057 D-022：Thread 创建来源（白名单过渡事实，不替代服务端 Manifest）。
///
/// 只有「消息页＋及等价已验证普通 AI 创建路径」允许写入 `manualOrdinaryAI`；
/// 医院/问诊会话必须使用真实业务绑定，不得以 provenance 冒充。
enum ThreadCreationOrigin: String, Codable, Sendable {
    /// 消息页「新建 AI 对话」创建的普通 Thread
    case manualOrdinaryAI = "manual_ordinary_ai"
    /// 院内就诊流程创建的医院会话
    case hospitalAgentFlow = "hospital_agent_flow"
    /// 线上问诊流程创建（预留）
    case telemedicineFlow = "telemedicine_flow"
    /// 跨设备同步/旧数据导入
    case imported
    /// 来源不明
    case unknown
}

/// 账号级 Thread 创建来源记录。
struct ThreadCreationProvenance: Codable, Equatable, Sendable {
    let threadID: UUID
    let origin: ThreadCreationOrigin
    let createdAt: Date

    nonisolated init(threadID: UUID, origin: ThreadCreationOrigin, createdAt: Date = Date()) {
        self.threadID = threadID
        self.origin = origin
        self.createdAt = createdAt
    }
}
