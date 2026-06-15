import Foundation

/// 首页宿主层唤起意图消费器
/// 专门承接首页就绪后路由意图分发逻辑，根据不同业务意图弹出全屏弹窗/Sheet页面，对接各个业务ViewModel
/// 所有UI状态操作限定在主线程执行
@MainActor
final class HomeLaunchIntentConsumer {
    /// 全局唤起意图调度协调器
    private let coordinator: LaunchIntentCoordinator
    /// 全局路由存储管理器
    private let routeStore: AppRouteStore
    /// 医疗文档上传业务视图模型
    private let uploadViewModel: MedicalDocumentUploadViewModel
    /// 首页根视图模型
    private let homeViewModel: HomeViewModel
    /// 日志工具实例
    private let logger: Logger

    /// 构造方法：依赖注入所有所需管理器、VM、日志实例
    init(
        coordinator: LaunchIntentCoordinator,
        routeStore: AppRouteStore,
        uploadViewModel: MedicalDocumentUploadViewModel,
        homeViewModel: HomeViewModel,
        logger: Logger
    ) {
        self.coordinator = coordinator
        self.routeStore = routeStore
        self.uploadViewModel = uploadViewModel
        self.homeViewModel = homeViewModel
        self.logger = logger
    }

    /// 标记首页宿主容器是否初始化就绪，回写给意图调度器更新就绪状态
    /// - Parameter ready: true=首页宿主加载完成；false=未就绪
    func setHomeHostReady(_ ready: Bool) {
        coordinator.updateReadiness { $0.homeHostReady = ready }
    }

    /// 就绪后执行意图消费入口：前置业务冲突校验、分发不同意图处理逻辑
    /// - Parameter setActiveFullScreenCover: 回调闭包，用于设置首页全屏弹窗标识，唤起对应全屏页
    func consumeIfReady(
        setActiveFullScreenCover: @escaping (HomeFullScreenCover?) -> Void
    ) async {
        // 无待处理唤起意图，直接退出
        guard let intent = coordinator.pendingIntent else { return }
        // 全局就绪条件不满足，暂不消费
        guard coordinator.readiness.canConsume else { return }

        // 分支1：医疗文档上传意图冲突校验
        switch intent {
        case .medicalDocumentUpload:
            // 上传弹窗已展示且并非文件选取阶段，正在处理上传流程，本次意图重试
            if uploadViewModel.isUploadPresented,
               uploadViewModel.stage != .picking {
                coordinator.finishConsumeFailed(
                    intent: intent,
                    reason: "upload_processing",
                    recoverable: true
                )
                return
            }

        // 分支2：成员邀请推送意图冲突校验
        case .memberInviteFromPush:
            // 首页已有弹出Sheet
            if let activeSheet = homeViewModel.activeSheet {
                if case .pendingInvites = activeSheet {
                    // 当前已经打开邀请列表页，无需重新弹窗，后续内部刷新高亮即可
                } else {
                    // 其他Sheet占用弹窗层级，冲突无法弹出，标记可重试
                    coordinator.finishConsumeFailed(
                        intent: intent,
                        reason: "home_sheet_busy",
                        recoverable: true
                    )
                    return
                }
            }

        // 分支3：通用路由意图一期暂不支持，永久丢弃不再重试
        case .appRoute:
            coordinator.finishConsumeFailed(
                intent: intent,
                reason: "unsupported_in_phase_one",
                recoverable: false
            )
            return
        }

        // 正式启动意图消费，做串行、去重二次校验
        guard let intent = coordinator.beginConsumingPendingIntent() else { return }
        // 路由导航至首页根页面，保证弹窗挂载宿主正确
        routeStore.route(to: .home, replaceStack: false)

        // 按意图类型分发具体消费逻辑
        switch intent {
        case .medicalDocumentUpload(let uploadIntent):
            let wrappedIntent = LaunchIntent.medicalDocumentUpload(uploadIntent)
            do {
                // 执行文档上传弹窗唤起逻辑
                try await consumeMedicalDocumentUpload(
                    uploadIntent,
                    setActiveFullScreenCover: setActiveFullScreenCover
                )
                // 消费成功，标记已处理并清空排队意图
                coordinator.commitConsumeSuccess(
                    intent: wrappedIntent,
                    target: "MedicalDocumentUploadHostView"
                )
            } catch {
                // 执行异常，标记可重试失败
                coordinator.finishConsumeFailed(
                    intent: wrappedIntent,
                    reason: error.localizedDescription,
                    recoverable: true
                )
            }

        case .memberInviteFromPush(let inviteIntent):
            let wrappedIntent = LaunchIntent.memberInviteFromPush(inviteIntent)
            do {
                // 打开邀请列表页面并定位对应邀请项
                try await consumeMemberInviteFromPush(inviteIntent)
                coordinator.commitConsumeSuccess(
                    intent: wrappedIntent,
                    target: "PendingMemberInvitesView"
                )
            } catch {
                coordinator.finishConsumeFailed(
                    intent: wrappedIntent,
                    reason: error.localizedDescription,
                    recoverable: true
                )
            }

        case .appRoute:
            // 重复兜底：一期不支持通用路由跳转
            coordinator.finishConsumeFailed(
                intent: intent,
                reason: "unsupported_in_phase_one",
                recoverable: false
            )
        }
    }

    /// 消费外部医疗文档上传意图：初始化上传VM、唤起全屏上传弹窗
    /// - Parameters:
    ///   - intent: 外部文档上传完整意图数据
    ///   - setActiveFullScreenCover: 设置全屏弹窗标识回调
    private func consumeMedicalDocumentUpload(
        _ intent: ExternalMedicalDocumentUploadIntent,
        setActiveFullScreenCover: @escaping (HomeFullScreenCover?) -> Void
    ) async throws {
        // 给上传VM灌入外部传入的本地文件数组，准备导入流程
        uploadViewModel.prepareForExternalImport(files: intent.files)
        // 触发弹出文档上传全屏页
        setActiveFullScreenCover(.medicalDocumentUpload)
        logger.info(
            "外部 PDF 已进入医疗文档上传页 documentID=\(intent.id)",
            module: .medical
        )

        // 让出线程执行UI渲染，二次确认弹窗挂载生效
        await Task.yield()
        setActiveFullScreenCover(.medicalDocumentUpload)
        logger.info(
            "外部 PDF 上传弹层已置位 cover=medicalDocumentUpload documentID=\(intent.id)",
            module: .medical
        )
    }

    /// 消费成员邀请推送点击意图：跳转邀请列表并高亮指定邀请
    /// - Parameter intent: 推送邀请完整意图数据
    private func consumeMemberInviteFromPush(_ intent: MemberInvitePushLaunchIntent) async throws {
        logger.info(
            "Push.memberInvite.interaction inviteID=\(intent.inviteID) notificationRequestID=\(intent.notificationRequestID ?? "nil")",
            module: .push
        )
        // 首页VM打开邀请列表，并定位到本次推送对应的邀请条目
        await homeViewModel.openPendingInvitesFromPush(inviteID: intent.inviteID)
    }
}
