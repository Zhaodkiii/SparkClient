import Foundation

/// 工具授权权限持久化存储类
/// 负责持久化保存每个工具的模型数据外传授权决策，保证线程安全
final class ToolConsentPermissionStore: @unchecked Sendable {
    /// 全局单例，提供统一的授权存储访问入口
    static let shared = ToolConsentPermissionStore()

    /// 用户偏好存储，用于本地持久化授权数据
    private let defaults: UserDefaults
    /// 存储授权工具列表的Key（带版本号，便于后续迭代兼容）
    private let key = "spark.tool_consent.allowed_tools.v1"
    /// 线程锁，保证多线程环境下读写数据的线程安全
    private let lock = NSLock()

    /// 初始化方法
    /// - Parameter defaults: 自定义存储对象，默认使用系统标准UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 判断指定工具是否已获得用户授权
    /// - Parameter toolName: 工具名称
    /// - Returns: 已授权返回true，未授权返回false
    func isAllowed(toolName: String) -> Bool {
        // 加锁，防止多线程同时读写导致数据异常
        lock.lock()
        // 代码执行完毕自动解锁，无论正常退出还是异常抛出
        defer { lock.unlock() }
        // 标准化工具名称后，检查是否在授权集合中
        return allowedTools().contains(Self.normalize(toolName))
    }

    /// 记录并持久化用户授权指定工具
    /// - Parameter toolName: 被授权的工具名称
    func rememberAllowed(toolName: String) {
        lock.lock()
        defer { lock.unlock() }
        // 获取当前已授权的工具集合
        var tools = allowedTools()
        // 插入标准化后的工具名（集合自动去重）
        tools.insert(Self.normalize(toolName))
        // 转换为有序数组并排序，保存到本地
        defaults.set(Array(tools).sorted(), forKey: key)
    }

    /// 从本地读取并返回所有已授权的工具名称集合
    /// - Returns: 无重复的工具名称集合
    private func allowedTools() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// 工具名称标准化处理：去除首尾空格换行 + 转为小写
    /// 避免因大小写、空格导致授权匹配失败
    private nonisolated static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// 苹果健康工具授权策略
/// 统一管控苹果健康工具结果离开设备用于模型上下文的授权策略
struct AppleHealthToolConsentPolicy: Sendable {
    /// 授权存储对象，默认使用全局单例
    private let permissionStore: ToolConsentPermissionStore

    /// 初始化方法
    /// - Parameter permissionStore: 自定义权限存储，默认使用全局共享实例
    init(permissionStore: ToolConsentPermissionStore = .shared) {
        self.permissionStore = permissionStore
    }

    /// 判断是否需要向用户请求健康工具授权
    /// - Parameters:
    ///   - result: 工具执行结果
    ///   - providerCompany: 服务提供方公司名称
    /// - Returns: 需要授权返回true，无需授权返回false
    func requiresConsent(result: ToolExecutionResult, providerCompany: String?) -> Bool {
        // 条件1：工具数据不敏感 → 无需授权
        guard result.sensitive else { return false }
        // 条件2：不是苹果健康读取工具 → 无需授权
        guard Self.appleHealthReadToolNames.contains(Self.normalize(result.toolName)) else { return false }
        // 条件3：本地服务（LOCAL）→ 无需授权
        guard (providerCompany ?? "").uppercased() != "LOCAL" else { return false }
        // 条件4：未获得用户授权 → 需要请求授权
        return permissionStore.isAllowed(toolName: result.toolName) == false
    }

    /// 记录用户授权的苹果健康工具
    /// - Parameter toolName: 工具名称
    func rememberAllowed(toolName: String) {
        permissionStore.rememberAllowed(toolName: toolName)
    }

    /// 苹果健康数据读取工具名称集合（已标准化）
    private static let appleHealthReadToolNames: Set<String> = Set([
        SparkToolName.fetchStepDetails.rawValue,
        SparkToolName.fetchEnergyDetails.rawValue,
        SparkToolName.fetchNutritionDetails.rawValue,
        SparkToolName.fetchSleepDetails.rawValue,
        SparkToolName.fetchWorkoutDetails.rawValue
    ].map { normalize($0) })

    /// 工具名称标准化（与权限存储类保持一致）
    private nonisolated static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
