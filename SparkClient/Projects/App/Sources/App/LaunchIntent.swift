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
    /// 通用路由跳转意图
    case appRoute(AppRouteLaunchIntent)

    /// 实现Identifiable协议，向外暴露意图唯一ID
    var id: UUID {
        switch self {
        case .medicalDocumentUpload(let intent):
            return intent.id
        case .memberInviteFromPush(let intent):
            return intent.id
        case .appRoute(let intent):
            return intent.id
        }
    }

    /// 意图消费优先级：数值越小优先级越高
    /// 0：邀请推送(最高) > 1：文档上传 > 3：普通路由(最低)
    var priority: Int {
        switch self {
        case .memberInviteFromPush:
            return 0
        case .medicalDocumentUpload:
            return 1
        case .appRoute:
            return 3
        }
    }
}

/// 唤起意图消费结果状态枚举
enum LaunchIntentConsumeResult: Equatable, Sendable {
    /// 消费成功，已正常执行跳转逻辑
    case consumed
    /// 未满足消费前置条件，暂缓处理
    case notReady
    /// 可恢复失败：稍后可重试消费，附带失败原因描述
    case failedRecoverable(String)
    /// 不可恢复致命失败：丢弃本次意图，附带失败原因描述
    case failedTerminal(String)
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
