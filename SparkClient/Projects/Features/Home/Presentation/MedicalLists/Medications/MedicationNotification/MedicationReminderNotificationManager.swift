import Foundation
import UserNotifications

/// 用药提醒系统通知管理器
/// 负责本地推送提醒的注册、全量重建、单条/批量清理、服药完成后移除对应提醒
@MainActor
final class MedicationReminderNotificationManager {
    /// 系统通知中心实例
    private let center: UNUserNotificationCenter
    /// 日志工具
    private let logger: Logger

    /// 初始化通知管理器，默认使用系统当前通知中心、控制台日志
    init(center: UNUserNotificationCenter = .current(), logger: Logger = ConsoleLogger()) {
        self.center = center
        self.logger = logger
    }

    /// 全量重建当前账号所有用药提醒
    /// - Parameters:
    ///   - events: 待注册的提醒事件数组
    ///   - accountID: 当前登录账号ID
    func rebuild(events: [MedicationReminderEvent], accountID: Int64) async {
        // 先清空该账号全部旧提醒
        await removeAllMedicationNotifications(forAccountID: accountID)
        // 批量注册新提醒事件
        for event in events {
            await register(event: event)
        }
    }

    /// 注册单条用药本地推送提醒
    /// - Parameter event: 用药提醒事件模型（标题、内容、触发时间、业务载荷）
    func register(event: MedicationReminderEvent) async {
        // 组装通知展示内容
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        // 写入业务数据载荷，点击通知后页面可解析
        content.userInfo = MedicationReminderPayloadParser.userInfo(for: event)

        // 提取时分日月年构建日历触发器，一次性提醒不重复
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: event.scheduledAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        // 构建通知请求，唯一标识使用事件ID
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: trigger)

        do {
            try await center.add(request)
            logger.debug("用药提醒注册成功 id=\(event.id)", module: .push)
        } catch {
            logger.warning("用药提醒注册失败 id=\(event.id) error=\(error.localizedDescription)", module: .push)
        }
    }

    /// 删除单条指定ID的通知（待推送+已推送全部清除）
    /// - Parameter id: 通知唯一标识符
    func removeNotification(id: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// 清空指定账号下全部用药类本地通知
    /// - Parameter accountID: 登录账号ID，用于匹配通知ID前缀过滤
    func removeAllMedicationNotifications(forAccountID accountID: Int64) async {
        // 获取该账号通知统一前缀
        let prefix = MedicationReminderNotification.identifierPrefix(accountID: accountID)
        // 获取所有待推送、已弹出通知
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()

        // 筛选出当前账号下所有用药提醒ID
        let pendingIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        let deliveredIDs = delivered
            .map(\.request.identifier)
            .filter { $0.hasPrefix(prefix) }

        // 去重合并所有通知ID
        let allIDs = Array(Set(pendingIDs + deliveredIDs))
        guard !allIDs.isEmpty else { return }

        // 批量移除待推送、已推送通知
        center.removePendingNotificationRequests(withIdentifiers: allIDs)
        center.removeDeliveredNotifications(withIdentifiers: allIDs)
        logger.debug("用药提醒已清理 count=\(allIDs.count) accountID=\(accountID)", module: .push)
    }

    /// 服药打卡完成后，批量移除对应时段、对应剂次的用药提醒
    /// - Parameters:
    ///   - completedItems: 已完成服药的剂次列表
    ///   - memberID: 当前家庭成员ID
    ///   - accountID: 登录账号ID
    ///   - scheduledAt: 本次服药对应的提醒时间
    func removeNotifications(
        containing completedItems: [MedicationReminderLaunchItem],
        memberID: Int,
        accountID: Int64,
        scheduledAt: Date
    ) async {
        let prefix = MedicationReminderNotification.identifierPrefix(accountID: accountID)
        // 生成时间标识，用于过滤同一天同一时段提醒
        let minuteToken = minuteToken(for: scheduledAt)
        // 组装已完成剂次唯一键：计划ID:剂次序号
        let completedKeys = Set(completedItems.map { "\($0.planID):\($0.doseSequence)" })

        // 获取所有待推送、已送达通知请求
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let requests = pending + delivered.map(\.request)

        // 过滤匹配条件的通知：账号前缀+成员ID+对应时段，且包含已完成剂次
        let targets = requests.compactMap { request -> String? in
            guard request.identifier.hasPrefix(prefix),
                  request.identifier.contains("_\(memberID)_"),
                  request.identifier.contains(minuteToken) else {
                return nil
            }
            // 解析通知载荷，判断是否包含已完成服药剂次
            guard let payload = MedicationReminderPayloadParser.parse(userInfo: request.content.userInfo) else {
                // 载荷解析失败，直接删除该通知避免残留
                return request.identifier
            }
            let containsCompleted = payload.items.contains {
                completedKeys.contains("\($0.planID):\($0.doseSequence)")
            }
            return containsCompleted ? request.identifier : nil
        }

        guard !targets.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: targets)
        center.removeDeliveredNotifications(withIdentifiers: targets)
        logger.debug("用药提醒已按剂次清理 count=\(targets.count)", module: .push)
    }

    /// 私有工具：根据日期生成时分秒时间标识串，用于匹配同时段提醒
    /// - Parameter date: 目标提醒时间
    /// - Returns: 格式 YYYYMMDD_HHMM 字符串
    private func minuteToken(for date: Date) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d%02d%02d_%02d%02d",
                      comps.year ?? 0,
                      comps.month ?? 0,
                      comps.day ?? 0,
                      comps.hour ?? 0,
                      comps.minute ?? 0)
    }

    /// 读取当前账号在本机通知中心中的用药提醒（待发送 + 已送达）。
    func fetchMedicationNotifications(forAccountID accountID: Int64) async -> [MedicationReminderNotificationRecord] {
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let now = Date()

        let pendingRequests = pending.filter { Self.belongsToMedicationReminder($0, accountID: accountID) }
        let pendingIDs = Set(pendingRequests.map(\.identifier))

        var records: [MedicationReminderNotificationRecord] = pendingRequests.map { request in
            makeRecord(from: request, isPending: true, deliveredAt: nil, now: now)
        }

        let deliveredOnly = delivered.filter { notification in
            let request = notification.request
            guard Self.belongsToMedicationReminder(request, accountID: accountID) else { return false }
            return pendingIDs.contains(request.identifier) == false
        }
        records.append(contentsOf: deliveredOnly.map { notification in
            makeRecord(
                from: notification.request,
                isPending: false,
                deliveredAt: notification.date,
                now: now
            )
        })

        return records.sorted { lhs, rhs in
            let left = lhs.scheduledAt ?? lhs.deliveredAt ?? .distantFuture
            let right = rhs.scheduledAt ?? rhs.deliveredAt ?? .distantFuture
            if left != right { return left < right }
            return lhs.notificationID < rhs.notificationID
        }
    }

    static func belongsToMedicationReminder(_ request: UNNotificationRequest, accountID: Int64) -> Bool {
        let prefix = MedicationReminderNotification.identifierPrefix(accountID: accountID)
        if request.identifier.hasPrefix(prefix) {
            return true
        }
        guard let payload = MedicationReminderPayloadParser.parse(userInfo: request.content.userInfo) else {
            return false
        }
        return payload.accountID == accountID
    }

    private func makeRecord(
        from request: UNNotificationRequest,
        isPending: Bool,
        deliveredAt: Date?,
        now: Date
    ) -> MedicationReminderNotificationRecord {
        let payload = MedicationReminderPayloadParser.parse(userInfo: request.content.userInfo)
        let triggerDate = request.trigger?.scheduledFireDate
        let scheduledAt = payload?.scheduledAt ?? triggerDate

        let status: MedicationReminderNotificationRecordStatus
        if payload == nil {
            status = .invalid
        } else if isPending {
            if let scheduledAt, scheduledAt < now {
                status = .expired
            } else {
                status = .pending
            }
        } else {
            status = .delivered
        }

        return MedicationReminderNotificationRecord(
            notificationID: request.identifier,
            status: status,
            scheduledAt: scheduledAt,
            deliveredAt: deliveredAt,
            title: request.content.title,
            body: request.content.body,
            payload: payload
        )
    }
}

private extension UNNotificationTrigger {
    var scheduledFireDate: Date? {
        if let calendarTrigger = self as? UNCalendarNotificationTrigger {
            return calendarTrigger.nextTriggerDate()
        }
        if let intervalTrigger = self as? UNTimeIntervalNotificationTrigger {
            return intervalTrigger.nextTriggerDate()
        }
        return nil
    }
}
