import Foundation

// MARK: - 用药提醒事件底层模型
/// 单条用药提醒内包含的药品剂次明细
struct MedicationReminderItem: Equatable, Sendable, Codable {
    /// 所属服药计划ID
    let planID: Int
    /// 当前剂次序号（第几次服药）
    let doseSequence: Int
    /// 药品名称
    let drugName: String
    /// 本次计划服用剂量文案
    let plannedDose: String
}

/// 完整单条本地推送提醒事件模型
struct MedicationReminderEvent: Identifiable, Equatable, Sendable {
    /// 通知唯一标识ID
    let id: String
    /// 当前登录账号ID
    let accountID: Int64
    /// 家庭成员ID
    let memberID: Int
    /// 提醒触发时间
    let scheduledAt: Date
    /// 展示用时间格式化文本
    let timeText: String
    /// 本次提醒包含的全部药品剂次列表
    let items: [MedicationReminderItem]
    /// 通知标题
    let title: String
    /// 通知正文内容
    let body: String
}

/// 生成用药提醒所需的完整入参结构体
struct MedicationReminderCompileInput: Sendable {
    /// 登录账号ID
    let accountID: Int64
    /// 家庭成员ID
    let memberID: Int
    /// 成员展示昵称
    let memberDisplayName: String
    /// 是否为本人（当前登录人）
    let isSelfMember: Bool
    /// 该成员全部服药计划
    let plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    /// 今日已完成服药打卡记录
    let records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    /// 当前基准时间
    let now: Date
    /// 向前/向后生成提醒的天数窗口
    let windowDays: Int
    /// 日历实例（统一时区、规则）
    let calendar: Calendar
    /// 通知弹窗是否展示药品名称
    let showsDrugNameInNotification: Bool
}

/// 编译生成提醒事件后的返回结果
struct MedicationReminderCompileResult: Equatable, Sendable {
    /// 最终待注册的全部推送提醒事件数组
    let events: [MedicationReminderEvent]
    /// 因超出最大提醒数量限制而截断丢弃的事件数量
    let truncatedCount: Int
}

// MARK: - 通知点击跳转启动载荷模型
/// 点击用药通知后透传给执行页面的完整载荷
struct MedicationReminderLaunchPayload: Codable, Equatable, Sendable {
    /// 账号ID
    let accountID: Int64
    /// 成员ID
    let memberID: Int
    /// 提醒原定触发时间
    let scheduledAt: Date
    /// 对应系统通知唯一ID
    let notificationID: String
    /// 本次通知关联的服药剂次列表
    let items: [MedicationReminderLaunchItem]
}

/// 通知载荷内的单条服药剂次标识（仅存ID，轻量化）
struct MedicationReminderLaunchItem: Codable, Equatable, Sendable, Hashable {
    /// 服药计划ID
    let planID: Int
    /// 剂次序号
    let doseSequence: Int
}

/// 从通知跳转至服药执行页时，页面需要聚焦的初始数据
struct MedicationExecutionInitialFocus: Equatable, Hashable, Sendable {
    /// 提醒时间
    let scheduledAt: Date
    /// 需要高亮展示的服药剂次
    let items: [MedicationReminderLaunchItem]
    /// 是否自动弹出打卡记录编辑弹窗
    let shouldOpenLogSheet: Bool
}

/// 查询家庭成员是否支持生成用药提醒的状态枚举
enum MedicationReminderMemberLookupResult: Equatable {
    /// 正常可用，可生成提醒
    case available
    /// 数据加载中
    case loading
    /// 不可用（无计划/无权限/数据异常）
    case unavailable
}

// MARK: - 提醒管理页面UI展示模型
/// 通知在管理页的展示状态
enum MedicationReminderDisplayStatus: Equatable, Sendable {
    /// 待推送（定时未触发）
    case pending
    /// 已推送至系统通知栏
    case delivered
    /// 已过期（时间超过未点击）
    case expired
    /// 无效通知（数据异常、已删除）
    case invalid
}

/// 管理页面单药品剂次展示单元
struct MedicationReminderDisplayItem: Identifiable, Equatable, Sendable {
    /// 本条明细唯一ID
    let id: String
    /// 服药计划ID
    let planID: Int
    /// 剂次序号
    let doseSequence: Int
    /// 药品名称（可选，异常时为空）
    let drugName: String?
}

/// 管理页面按单条通知聚合的展示分组
struct MedicationReminderDisplayGroup: Identifiable, Equatable, Sendable {
    /// 分组唯一ID
    let id: String
    /// 系统通知原始ID
    let notificationID: String
    /// 关联成员ID，无则为空
    let memberID: Int?
    /// 成员名称
    let memberName: String
    /// 提醒触发时间
    let scheduledAt: Date?
    /// 当前通知状态
    let status: MedicationReminderDisplayStatus
    /// 分组内全部药品剂次明细
    let items: [MedicationReminderDisplayItem]
    /// 通知原始正文文案
    let rawBody: String
}

/// 本地通知数据库记录状态枚举（与UI展示状态对齐）
enum MedicationReminderNotificationRecordStatus: Equatable, Sendable {
    case pending
    case delivered
    case expired
    case invalid
}

/// 持久化存储的完整通知记录模型
struct MedicationReminderNotificationRecord: Equatable, Sendable {
    /// 通知唯一ID
    let notificationID: String
    /// 通知状态
    let status: MedicationReminderNotificationRecordStatus
    /// 计划触发时间
    let scheduledAt: Date?
    /// 实际推送送达时间
    let deliveredAt: Date?
    /// 通知标题
    let title: String
    /// 通知正文
    let body: String
    /// 跳转业务载荷（解析失败为nil）
    let payload: MedicationReminderLaunchPayload?
}

// MARK: - 用药通知全局常量定义
enum MedicationReminderNotification {
    /// 通知类型标识，用于区分其他业务推送
    static let type = "medication_reminder"
    /// 路由标识：点击跳转服药执行页
    static let route = "medication_execution"
    /// 默认生成提醒的时间窗口天数
    static let defaultWindowDays = 7
    /// 最大支持生成提醒的窗口天数上限
    static let maxWindowDays = 14
    /// 单个账号最多同时存在待推送通知条数上限
    static let maxPendingCount = 48
    /// 重建提醒防抖间隔（避免短时间重复刷新）
    static let rebuildDebounceSeconds: TimeInterval = 30
    /// 前台活跃状态下，允许主动重建提醒的时间阈值
    static let foregroundRebuildThresholdSeconds: TimeInterval = 300

    /// 根据账号ID生成通知ID统一前缀，用于批量清理同账号通知
    static func identifierPrefix(accountID: Int64) -> String {
        "medication_\(accountID)_"
    }
}

extension Notification.Name {
    /// 用药提醒偏好设置发生变更时发送系统通知
    static let medicationReminderPreferencesChanged = Notification.Name("medicationReminderPreferencesChanged")
}

// MARK: - 通知userInfo载荷解析工具类
/// 系统通知userInfo字典与业务模型互转工具
enum MedicationReminderPayloadParser {
    /// 从通知原始userInfo字典解析出跳转载荷
    static func parse(userInfo: [AnyHashable: Any]) -> MedicationReminderLaunchPayload? {
        // 校验通知业务类型，非用药提醒直接返回空
        guard (userInfo["type"] as? String) == MedicationReminderNotification.type else { return nil }

        // 兼容数字/字符串两种格式读取账号ID
        let accountID = (userInfo["account_id"] as? Int64)
            ?? (userInfo["account_id"] as? Int).map(Int64.init)
            ?? (userInfo["account_id"] as? String).flatMap(Int64.init)
        // 兼容数字/字符串读取成员ID
        let memberID = (userInfo["member_id"] as? Int)
            ?? (userInfo["member_id"] as? String).flatMap(Int.init)
        // 通知唯一ID
        let notificationID = userInfo["notification_id"] as? String
        // ISO8601格式时间字符串
        let scheduledAtRaw = userInfo["scheduled_at"] as? String

        // 基础字段缺失直接解析失败
        guard let accountID, let memberID, let notificationID, let scheduledAtRaw else { return nil }
        // 时间字符串转Date失败则丢弃本条载荷
        guard let scheduledAt = decodeISO8601String(scheduledAtRaw) else { return nil }

        // 解析药品剂次数组
        let items = parseItems(userInfo["items"])
        guard !items.isEmpty else { return nil }

        return MedicationReminderLaunchPayload(
            accountID: accountID,
            memberID: memberID,
            scheduledAt: scheduledAt,
            notificationID: notificationID,
            items: items
        )
    }

    /// 将提醒事件模型转换为系统通知所需userInfo字典
    static func userInfo(for event: MedicationReminderEvent) -> [String: Any] {
        [
            "type": MedicationReminderNotification.type,
            "route": MedicationReminderNotification.route,
            "account_id": event.accountID,
            "member_id": event.memberID,
            "scheduled_at": MedicalDateCoding.encodeISO8601(event.scheduledAt),
            "notification_id": event.id,
            "items": event.items.map { item in
                [
                    "plan_id": item.planID,
                    "dose_sequence": item.doseSequence
                ] as [String: Any]
            }
        ]
    }

    /// 批量解析原始数组为服药剂次载荷数组
    private static func parseItems(_ raw: Any?) -> [MedicationReminderLaunchItem] {
        guard let array = raw as? [[String: Any]] else {
            // 兼容外层为Any数组的异常结构
            if let array = raw as? [Any] {
                return array.compactMap { element in
                    guard let dict = element as? [String: Any] else { return nil }
                    return parseItem(dict)
                }
            }
            return []
        }
        return array.compactMap(parseItem)
    }

    /// 单条字典解析为轻量化服药剂次模型
    private static func parseItem(_ dict: [String: Any]) -> MedicationReminderLaunchItem? {
        // 兼容数字、字符串两种ID格式
        let planID = (dict["plan_id"] as? Int) ?? (dict["plan_id"] as? String).flatMap(Int.init)
        let doseSequence = (dict["dose_sequence"] as? Int) ?? (dict["dose_sequence"] as? String).flatMap(Int.init)
        guard let planID, let doseSequence else { return nil }
        return MedicationReminderLaunchItem(planID: planID, doseSequence: doseSequence)
    }

    /// 兼容带毫秒/不带毫秒两种ISO8601时间字符串解码
    private static func decodeISO8601String(_ value: String) -> Date? {
        // 优先使用带毫秒解析器
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) {
            return date
        }
        // 失败则使用标准无毫秒解析器兜底
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }
}
