import Combine
import Foundation

/// App 级冷启动目标页面公共调度器（业务编号：APP-COLD-ROUTE-000001）
/// 统一接收、排队、优先级裁决、就绪校验、消费拉起意图，管控外部唤起、推送点击、URL跳转等路由分发
/// 所有UI操作限定在主线程执行，通过@Published向外暴露状态，视图可订阅响应
@MainActor
final class LaunchIntentCoordinator: ObservableObject {
    /// 当前待消费的唤起意图，外部只读
    @Published private(set) var pendingIntent: LaunchIntent?
    /// 应用初始化就绪状态合集，用于判断是否可以执行路由跳转，外部只读
    @Published private(set) var readiness = LaunchIntentReadiness()

    /// 日志工具实例
    private let logger: Logger
    /// 已成功消费过的意图ID集合，用于去重，避免重复执行同一跳转
    private var consumedIntentIDs: Set<UUID> = []
    /// 当前正在处理中的意图ID，防止并发同时消费多个意图
    private var consumingIntentID: UUID?

    /// 初始化注入日志实例
    /// - Parameter logger: 统一日志管理器
    init(logger: Logger) {
        self.logger = logger
    }

    /// 接收新的外部唤起意图，做去重、优先级判断、替换待处理队列
    /// - Parameter intent: 接收到的拉起意图对象
    func receive(_ intent: LaunchIntent) {
        // 该意图已经消费过，直接丢弃并打日志
        if consumedIntentIDs.contains(intent.id) {
            logger.info(
                "LaunchIntent.discard id=\(intent.id) reason=already_consumed type=\(intent.logType)",
                module: .general
            )
            return
        }

        // 判断是否要用新意图覆盖当前排队中的旧意图
        if shouldReplacePending(with: intent) {
            pendingIntent = intent
            logger.info(
                "LaunchIntent.receive id=\(intent.id) type=\(intent.logType) source=\(intent.logSource)",
                module: .general
            )
            // 若当前未就绪，打印阻塞原因日志
            logPendingIfBlocked(intentID: intent.id)
        }
    }

    /// 批量更新应用就绪状态，状态无变更则不触发视图刷新
    /// - Parameter transform: 外部传入闭包修改readiness内部字段
    func updateReadiness(_ transform: (inout LaunchIntentReadiness) -> Void) {
        let before = readiness
        transform(&readiness)
        // 状态未发生任何变化，直接返回
        guard before != readiness else { return }
        // 更新后满足消费条件，打印就绪日志
        if readiness.canConsume {
            logger.debug("LaunchIntent.readiness ready accountID=\(readiness.accountID.map(String.init) ?? "nil")", module: .general)
        }
    }

    /// 清空所有排队意图、已消费记录、处理中标记，用于场景重置/登出清空路由
    /// - Parameter reason: 清空原因，用于日志排查
    func discardAll(reason: String) {
        // 打印被丢弃的待处理意图日志
        if let pendingIntent {
            logger.info(
                "LaunchIntent.discard id=\(pendingIntent.id) reason=\(reason) type=\(pendingIntent.logType)",
                module: .general
            )
        }
        pendingIntent = nil
        consumedIntentIDs.removeAll()
        consumingIntentID = nil
    }

    /// 开始尝试消费排队中的意图，做多重前置校验
    /// - Returns: 校验通过返回待消费意图；不满足条件返回nil
    /// 说明：仅标记正在处理，意图不会立即从pending移除，等待上层回调成功/失败后再清理
    func beginConsumingPendingIntent() -> LaunchIntent? {
        // 无排队意图
        guard let intent = pendingIntent else { return nil }
        // 应用未就绪，不能消费
        guard readiness.canConsume else {
            logPendingIfBlocked(intentID: intent.id)
            return nil
        }
        // 该意图已经处理过
        guard consumedIntentIDs.contains(intent.id) == false else { return nil }
        // 已有意图正在处理，串行排队不并发
        guard consumingIntentID == nil else { return nil }

        // 标记当前意图正在消费中
        consumingIntentID = intent.id
        logger.info(
            "LaunchIntent.consume.start id=\(intent.id) type=\(intent.logType)",
            module: .general
        )
        return intent
    }

    /// 意图消费成功回调：标记已消费、清空排队与处理中标记
    /// - Parameters:
    ///   - intent: 执行成功的意图实例
    ///   - target: 跳转目标页面标识，日志定位用
    func commitConsumeSuccess(intent: LaunchIntent, target: String) {
        consumedIntentIDs.insert(intent.id)
        // 若当前排队项就是本次意图，清空待处理
        if pendingIntent?.id == intent.id {
            pendingIntent = nil
        }
        consumingIntentID = nil
        logger.info(
            "LaunchIntent.consume.success id=\(intent.id) type=\(intent.logType) target=\(target)",
            module: .general
        )
    }

    /// 意图消费失败收尾处理，区分可重试/不可重试两种失败分支
    /// - Parameters:
    ///   - intent: 执行失败的意图实例
    ///   - reason: 失败原因描述
    ///   - recoverable: true=可恢复失败，放回队列稍后重试；false=致命失败，永久丢弃
    func finishConsumeFailed(intent: LaunchIntent, reason: String, recoverable: Bool) {
        // 无论失败类型，最终都要清空正在处理标记
        defer { consumingIntentID = nil }

        // 可恢复失败：保留在pending队列，下次就绪后重试
        if recoverable {
            if pendingIntent == nil {
                pendingIntent = intent
            }
            logger.warning(
                "LaunchIntent.consume.failed id=\(intent.id) type=\(intent.logType) reason=\(reason) recoverable=true",
                module: .general
            )
            return
        }

        // 不可恢复失败：标记已消费，永久丢弃不再重试
        consumedIntentIDs.insert(intent.id)
        if pendingIntent?.id == intent.id {
            pendingIntent = nil
        }
        logger.warning(
            "LaunchIntent.consume.failed id=\(intent.id) type=\(intent.logType) reason=\(reason) recoverable=false",
            module: .general
        )
    }

    /// 私有规则：判断新到来的意图是否覆盖当前pending里的旧意图
    /// 规则：无旧意图直接替换；同邀请ID重复推送强制覆盖；新意图优先级更高则覆盖
    /// - Parameter incoming: 新接收的意图
    /// - Returns: true=覆盖；false=丢弃新意图保留旧的
    private func shouldReplacePending(with incoming: LaunchIntent) -> Bool {
        guard let existing = pendingIntent else { return true }

        // 同一条成员邀请推送重复触发，直接覆盖旧意图
        if case .memberInviteFromPush(let existingInvite) = existing,
           case .memberInviteFromPush(let incomingInvite) = incoming,
           existingInvite.inviteID == incomingInvite.inviteID {
            return true
        }

        // 新意图优先级数值 ≤ 旧意图（优先级更高或同级），执行替换
        if incoming.priority <= existing.priority {
            return true
        }
        return false
    }

    /// 意图进入排队但应用未就绪，打印详细阻塞原因日志，方便排查冷启动路由卡住问题
    /// - Parameter intentID: 被阻塞的意图唯一ID
    private func logPendingIfBlocked(intentID: UUID) {
        guard readiness.canConsume == false else { return }
        let reason: String
        // 逐级判断是哪个就绪条件不满足
        if readiness.isSignedIn == false {
            reason = "app_not_ready sessionState=signedOut"
        } else if readiness.isAccountPrepared == false {
            reason = "account_not_prepared accountID=\(readiness.accountID.map(String.init) ?? "nil")"
        } else if readiness.isOnboardingBlocking {
            reason = "onboarding_blocking"
        } else if readiness.mainTabReady == false {
            reason = "main_tab_not_ready"
        } else if readiness.homeHostReady == false {
            reason = "home_host_not_ready"
        } else {
            reason = "unknown"
        }
        logger.info("LaunchIntent.pending id=\(intentID) reason=\(reason)", module: .general)
    }
}

// MARK: - LaunchIntent 日志扩展属性
private extension LaunchIntent {
    /// 日志打印用：意图类型字符串标识
    var logType: String {
        switch self {
        case .medicalDocumentUpload:
            return "medicalDocumentUpload"
        case .memberInviteFromPush:
            return "memberInviteFromPush"
        case .appRoute:
            return "appRoute"
        }
    }

    /// 日志打印用：唤起来源原始字符串
    var logSource: String {
        switch self {
        case .medicalDocumentUpload(let intent):
            return intent.source.rawValue
        case .memberInviteFromPush(let intent):
            return intent.source.rawValue
        case .appRoute(let intent):
            return intent.source.rawValue
        }
    }
}
