import Foundation

/// 任务来源类型（本地 / 服务端）
enum TaskSource: String, Codable, Sendable {
    case local = "Local"    // 本地任务
    case service = "Service" // 服务端任务
}

/// 小任务模型（客户端核心数据结构）
/// 与后端 Django SmallTask 模型字段一一对应
struct SmallTask: Codable, Identifiable, Equatable, Sendable {
    // MARK: - 模型属性
    /// 来源ID（对应后端主键 id）
    var sourceID: Int
    
    /// 任务名称
    var name: String
    
    /// 唯一编码（用于路由，如 Local_1 / Service_2）
    var code: String
    
    /// 任务简介（短描述）
    var brief: String
    
    /// 完整任务规则 / Prompt
    var prompt: String
    
    /// 任务图标名称/URL
    var icon: String
    
    /// 调用工具列表
    var toolList: [String]

    /// 任务来源（本地/服务端）
    var source: TaskSource

    // MARK: - Identifiable 协议实现
    /// 任务唯一标识（优先使用 code，不存在则自动拼接生成）
    var id: String {
        code.isEmpty ? "\(source.rawValue)_\(sourceID)" : code
    }

    // MARK: - JSON 编码映射键
    enum CodingKeys: String, CodingKey {
        case sourceID = "id"       // 映射后端字段 id
        case name, code, brief, prompt, icon, source
        case toolList = "tool_list" // 映射后端字段 tool_list
    }

    // MARK: - 构造器
    /// 完整初始化方法
    init(
        sourceID: Int,
        name: String,
        code: String,
        brief: String,
        prompt: String,
        icon: String,
        toolList: [String],
        source: TaskSource
    ) {
        self.sourceID = sourceID
        self.name = name
        self.code = code
        self.brief = brief
        self.prompt = prompt
        self.icon = icon
        self.toolList = toolList
        self.source = source
    }

    // MARK: - 便捷创建方法
    /// 快速创建【本地任务】（自动生成 code）
    static func createLocalTask(
        id: Int,
        name: String,
        brief: String,
        prompt: String,
        icon: String,
        toolList: [String]
    ) -> SmallTask {
        SmallTask(
            sourceID: id,
            name: name,
            code: "Local_\(id)", // 自动生成本地任务编码
            brief: brief,
            prompt: prompt,
            icon: icon,
            toolList: toolList,
            source: .local
        )
    }
}
