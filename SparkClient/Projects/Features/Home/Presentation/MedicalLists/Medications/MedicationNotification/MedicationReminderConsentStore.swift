import Foundation

/// 设备本地用药提醒授权记录模型
/// 说明：仅代表当前登录账号，同意在本设备为非本人家庭成员生成本地用药提醒
/// 1. 该授权仅本地存储，不会同步至服务端，不属于家庭成员云端权限
/// 2. 多设备独立生效，跨设备提醒授权策略后续单独迭代设计
struct MedicationReminderMemberConsent: Codable, Equatable, Sendable {
    /// 当前登录账号ID
    let accountID: Int64
    /// 家庭成员成员ID
    let memberID: Int
    /// 是否允许为本成员创建本地用药提醒
    var allowsLocalReminder: Bool
    /// 用户作出授权/拒绝操作的时间
    var decidedAt: Date
    /// 操作来源标记（页面/弹窗/导入等，用于埋点溯源）
    var source: String
}

/// 用药提醒本地授权持久化存储管理器
/// 基于UserDefaults存储设备级授权记录，线程安全Sendable
final class MedicationReminderConsentStore: Sendable {
    /// 单例全局实例
    static let shared = MedicationReminderConsentStore()

    /// 底层持久化容器
    private let userDefaults: UserDefaults

    /// 初始化，默认使用标准UserDefaults，单元测试可注入自定义实例
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// 查询指定账号+成员是否允许本地用药提醒
    /// - Parameters:
    ///   - accountID: 当前账号ID
    ///   - memberID: 家庭成员ID
    /// - Returns: 存在授权记录返回对应开关状态，无记录默认false
    func allowsLocalReminder(accountID: Int64, memberID: Int) -> Bool {
        load(accountID: accountID, memberID: memberID)?.allowsLocalReminder ?? false
    }

    /// 设置/更新成员本地提醒授权状态并持久化
    /// - Parameters:
    ///   - value: 是否允许本地提醒
    ///   - accountID: 当前账号ID
    ///   - memberID: 家庭成员ID
    ///   - source: 操作来源标识
    func setAllowsLocalReminder(_ value: Bool, accountID: Int64, memberID: Int, source: String) {
        // 组装最新授权记录，操作时间取当前时间
        let consent = MedicationReminderMemberConsent(
            accountID: accountID,
            memberID: memberID,
            allowsLocalReminder: value,
            decidedAt: Date(),
            source: source
        )
        // JSON编码存入UserDefaults，编码失败静默丢弃
        if let data = try? JSONEncoder().encode(consent) {
            userDefaults.set(data, forKey: key(accountID: accountID, memberID: memberID))
        }
    }

    /// 删除单条账号+成员的授权记录
    /// - Parameters:
    ///   - accountID: 当前账号ID
    ///   - memberID: 家庭成员ID
    func removeConsent(accountID: Int64, memberID: Int) {
        userDefaults.removeObject(forKey: key(accountID: accountID, memberID: memberID))
    }

    /// 清空当前账号下全部成员的本地授权记录
    /// - Parameter accountID: 需要清空授权的账号ID
    func removeAllForAccount(_ accountID: Int64) {
        // 拼接存储Key前缀，遍历删除所有匹配前缀的记录
        let prefix = "medication_reminder_member_consent_v1_\(accountID)_"
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    /// 私有方法：加载指定账号+成员的授权记录
    /// - Parameters:
    ///   - accountID: 账号ID
    ///   - memberID: 成员ID
    /// - Returns: 存在有效记录返回模型实例，无数据/解码失败返回nil
    private func load(accountID: Int64, memberID: Int) -> MedicationReminderMemberConsent? {
        guard let data = userDefaults.data(forKey: key(accountID: accountID, memberID: memberID)) else {
            return nil
        }
        return try? JSONDecoder().decode(MedicationReminderMemberConsent.self, from: data)
    }

    /// 私有方法：生成唯一存储键名
    /// 格式：medication_reminder_member_consent_v1_账号ID_成员ID
    /// - Parameters:
    ///   - accountID: 账号ID
    ///   - memberID: 成员ID
    /// - Returns: UserDefaults存储Key字符串
    private func key(accountID: Int64, memberID: Int) -> String {
        "medication_reminder_member_consent_v1_\(accountID)_\(memberID)"
    }
}
