import Foundation

/// 应用唤起意图来源枚举
/// 标记本次App被拉起、跳转路由、接收通知的触发渠道
enum LaunchIntentSource: String, Sendable {
    /// 系统启动参数 launchOptions 冷启动触发
    case launchOptions
    /// Scene场景连接唤起（iOS 13+ SceneDelegate场景方式）
    case sceneConnection
    /// UIApplication 打开应用方式唤起
    case applicationOpen
    /// 通过URL Scheme/Universal Link外部跳转唤起
    case onOpenURL
    /// 用户点击远程推送通知触发
    case remoteNotificationInteraction
    /// 用户点击本地通知触发
    case localNotificationInteraction
    /// 应用内横幅通知点击触发
    case inAppNotificationBannerTap
}

/// 外部医疗文档上传唤起意图模型
/// 携带本地待上传文件列表，用于跳转文档上传页面
struct ExternalMedicalDocumentUploadIntent: Equatable, Sendable, Identifiable {
    /// 意图唯一标识
    let id: UUID
    /// 待上传本地医疗文件数组
    let files: [MedicalUploadLocalFile]
    /// 意图接收时间戳
    let receivedAt: Date
    /// 唤起来源渠道
    let source: LaunchIntentSource
    /// 原始跳转URL描述文本（可选，用于日志排查）
    let originalURLDescription: String?
}

/// 成员邀请推送通知唤起意图模型
/// 点击邀请推送后携带邀请信息，跳转邀请处理页面
struct MemberInvitePushLaunchIntent: Equatable, Sendable, Identifiable {
    /// 意图唯一标识
    let id: UUID
    /// 邀请记录唯一ID
    let inviteID: Int
    /// 意图接收时间戳
    let receivedAt: Date
    /// 唤起来源渠道
    let source: LaunchIntentSource
    /// 通知交互行为标识
    let actionIdentifier: String
    /// 系统通知请求唯一ID（可选）
    let notificationRequestID: String?
}

/// 用药提醒本地通知唤起意图模型
struct MedicationReminderLaunchIntent: Equatable, Sendable, Identifiable {
    let id: UUID
    let payload: MedicationReminderLaunchPayload
    let receivedAt: Date
    let source: LaunchIntentSource
    let notificationRequestID: String?
}

/// 健康资源变更 APNs 唤起意图（如用药计划被他人维护）。
struct HealthResourceChangedLaunchIntent: Equatable, Sendable, Identifiable {
    let id: UUID
    let memberID: Int
    let resourceType: String
    let resourceID: Int?
    let action: String
    let receivedAt: Date
    let source: LaunchIntentSource
    let notificationRequestID: String?
}

/// 通用页面路由跳转唤起意图模型
/// 统一承载App内部路由跳转指令
struct AppRouteLaunchIntent: Equatable, Sendable, Identifiable {
    /// 意图唯一标识
    let id: UUID
    /// 目标路由枚举（AppRoute为全局路由定义）
    let route: AppRoute
    /// 意图接收时间戳
    let receivedAt: Date
    /// 唤起来源渠道
    let source: LaunchIntentSource
}

/// 统一应用唤起意图总枚举
/// 聚合所有业务场景的拉起意图，统一管理、分发、消费
enum LaunchIntent: Equatable, Sendable, Identifiable {
    /// 医疗文档上传意图
    case medicalDocumentUpload(ExternalMedicalDocumentUploadIntent)
    /// 推送成员邀请跳转意图
    case memberInviteFromPush(MemberInvitePushLaunchIntent)
    /// 用药提醒本地通知跳转意图
    case medicationReminder(MedicationReminderLaunchIntent)
    /// 健康资源变更 APNs 跳转意图
    case healthResourceChanged(HealthResourceChangedLaunchIntent)
    /// 通用路由跳转意图
    case appRoute(AppRouteLaunchIntent)

    /// 实现Identifiable协议，向外暴露意图唯一ID
    var id: UUID {
        switch self {
        case .medicalDocumentUpload(let intent):
            return intent.id
        case .memberInviteFromPush(let intent):
            return intent.id
        case .medicationReminder(let intent):
            return intent.id
        case .healthResourceChanged(let intent):
            return intent.id
        case .appRoute(let intent):
            return intent.id
        }
    }

    /// 意图消费优先级：数值越小优先级越高
    /// 0：邀请推送(最高) > 1：文档上传 > 2：用药提醒 > 3：普通路由(最低)
    var priority: Int {
        switch self {
        case .memberInviteFromPush:
            return 0
        case .medicalDocumentUpload:
            return 1
        case .medicationReminder:
            return 2
        case .healthResourceChanged:
            return 2
        case .appRoute:
            return 3
        }
    }

    var memberInviteID: Int? {
        if case .memberInviteFromPush(let intent) = self {
            return intent.inviteID
        }
        return nil
    }

    var medicalUploadFileSignature: String? {
        guard case .medicalDocumentUpload(let intent) = self else { return nil }
        return intent.files.map(\.url.path).sorted().joined(separator: "|")
    }

    var appRouteSignature: String? {
        guard case .appRoute(let intent) = self else { return nil }
        return String(describing: intent.route)
    }

    var medicationReminderNotificationID: String? {
        guard case .medicationReminder(let intent) = self else { return nil }
        return intent.payload.notificationID
    }
}

/// 唤起意图消费结果状态枚举
enum LaunchIntentConsumeResult: Equatable, Sendable {
    /// 消费成功，已正常执行跳转逻辑
    case consumed
    /// 未满足消费前置条件，暂缓处理
    case notReady
    /// 可恢复失败：稍后可重试消费
    case failedRecoverable(LaunchIntentBlockedReason)
    /// 不可恢复致命失败：丢弃本次意图
    case failedTerminal(LaunchIntentBlockedReason)
}

/// 意图被阻塞的原因分类
enum LaunchIntentBlockedReason: String, Sendable {
    case signedOut
    case accountNotPrepared
    case onboardingBlocking
    case mainTabNotReady
    case homeHostNotReady
    case homeSheetBusy
    case fullScreenCoverBusy
    case uploadProcessing
    case unsupportedInPhase
}

/// 首页 Sheet 轻量类型（App 层 host state 用）
enum HomeSheetKind: String, Sendable {
    case addMember
    case pendingInvites
    case memberModuleSetup
    case share
    case taskCenter
}

/// 首页全屏 Cover 轻量类型
enum HomeFullScreenCoverKind: String, Sendable {
    case medicalDocumentUpload
    case customCamera
    case memberDetail
}

/// 首页宿主展示状态，由 HealthHomeView / IOS26HomeView 上报给调度器
struct LaunchIntentHostState: Equatable, Sendable {
    var activeSheetKind: HomeSheetKind?
    var activeFullScreenCoverKind: HomeFullScreenCoverKind?
    var isUploadProcessing = false

    var canPresentSheet: Bool {
        activeSheetKind == nil
    }

    var canPresentMemberInvite: Bool {
        activeSheetKind == nil || activeSheetKind == .pendingInvites
    }

    var canPresentMedicalUpload: Bool {
        isUploadProcessing == false
            && (activeFullScreenCoverKind == nil || activeFullScreenCoverKind == .medicalDocumentUpload)
    }
}

/// handler 对单条 intent 的可消费性判断
struct LaunchIntentAvailability: Equatable, Sendable {
    let canConsume: Bool
    let blockedReason: LaunchIntentBlockedReason?

    static let available = LaunchIntentAvailability(canConsume: true, blockedReason: nil)

    static func blocked(_ reason: LaunchIntentBlockedReason) -> LaunchIntentAvailability {
        LaunchIntentAvailability(canConsume: false, blockedReason: reason)
    }
}

/// 队列中的单条唤起意图
struct QueuedLaunchIntent: Identifiable, Equatable, Sendable {
    let id: UUID
    let intent: LaunchIntent
    let enqueuedAt: Date
    let sequence: Int64
    var attemptCount: Int
    var lastBlockedReason: LaunchIntentBlockedReason?
    var lastTriedAt: Date?

    init(intent: LaunchIntent, sequence: Int64, enqueuedAt: Date = Date()) {
        self.id = intent.id
        self.intent = intent
        self.enqueuedAt = enqueuedAt
        self.sequence = sequence
        self.attemptCount = 0
        self.lastBlockedReason = nil
        self.lastTriedAt = nil
    }
}

/// 入队合并策略
enum LaunchIntentCoalescingAction: Sendable {
    case keepBoth
    case replaceExisting
    case dropIncoming
    case updateExisting(index: Int)
}

/// 意图消费就绪状态校验模型
/// 聚合登录、账号初始化、引导页、首页模块加载等前置依赖状态
struct LaunchIntentReadiness: Equatable, Sendable {
    /// 当前登录账号ID（可选，未登录为nil）
    var accountID: Int64?
    /// 是否已完成账号登录
    var isSignedIn = false
    /// 账号信息、用户数据是否初始化完成
    var isAccountPrepared = false
    /// 是否存在阻塞性新手引导（true则禁止路由跳转）
    var isOnboardingBlocking = false
    /// 底部主Tab页面是否加载就绪
    var mainTabReady = false
    /// 首页宿主容器是否初始化完成
    var homeHostReady = false

    /// 综合判断：当前是否满足消费唤起意图的全部前置条件
    var canConsume: Bool {
        isSignedIn
            && isAccountPrepared
            && isOnboardingBlocking == false
            && mainTabReady
            && homeHostReady
    }
}
