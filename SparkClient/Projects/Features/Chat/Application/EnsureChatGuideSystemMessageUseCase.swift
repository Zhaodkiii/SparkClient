import Foundation

/// CHAT-000029 3.3：进入会话页面后幂等插入首条 system 引导卡片。
///
/// 职责：
/// 1. loadThread 获取稳定 memberID（默认绑定已在 thread 创建阶段前置完成）；
/// 2. loadMessages 判断是否已有 guide card（幂等，不重复插入）；
/// 3. 调用 ChatGuideCardPayloadBuilder 构建初始 payload；
/// 4. 调用 ChatGuideSystemMessageFactory 创建 system message 并 appendMessage；
/// 5. 返回插入后的 message/block target，供科普问题生成使用。
///
/// 初始 payload 状态：
/// - thread.memberID 非空：questions=[]、state=generating、memberID=thread.memberID；
/// - thread.memberID 为空：questions=preset、state=preset、source=preset。
struct EnsureChatGuideSystemMessageUseCase: Sendable {
    struct Output: Sendable {
        /// 当前 guide 卡片定位（已存在或本次新插入）；nil 表示无可用卡片
        var target: ChatGuideGuideCardTarget?
        /// 本次是否实际插入了新 guide message
        var didInsert: Bool
    }

    let repository: any ChatRepository
    /// 引导卡片数据聚合器；nil 时不插入（测试 / 访客链路）。
    let guideCardBuilder: ChatGuideCardPayloadBuilder?
    let accessGate: HealthDataAccessGate
    let logger: Logger

    init(
        repository: any ChatRepository,
        guideCardBuilder: ChatGuideCardPayloadBuilder?,
        accessGate: HealthDataAccessGate = .shared,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.guideCardBuilder = guideCardBuilder
        self.accessGate = accessGate
        self.logger = logger
    }

    func execute(threadID: UUID) async -> Output {
        guard let guideCardBuilder else {
            return Output(target: nil, didInsert: false)
        }
        guard let thread = await repository.loadThread(id: threadID) else {
            return Output(target: nil, didInsert: false)
        }

        // 幂等：thread 已有引导卡片时直接返回现有 target，不补插第二条
        let existing = await repository.loadMessages(threadID: threadID, limit: 50, before: nil)
        if let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: existing) {
            return Output(target: target, didInsert: false)
        }

        // 默认绑定已在 thread 创建阶段解析完成（CHAT-000029 3.1），
        // 此处不再依赖 defaultMemberBindingEnabled 推迟初始状态。
        let healthAccess = await healthDataAccessResult(memberID: thread.memberID)
        logger.info(
            "chat.guide.metrics.initial_access thread=\(String(threadID.uuidString.prefix(8))) member=\(thread.memberID.map(String.init) ?? "nil") granted=\(healthAccess.isGranted) reason=\(Self.logReason(for: healthAccess))",
            module: .general
        )
        let payload = await guideCardBuilder.build(
            memberID: thread.memberID,
            healthDataAuthorized: healthAccess.isGranted
        )
        let message = ChatGuideSystemMessageFactory.make(threadID: threadID, payload: payload)
        do {
            let inserted = try await repository.appendMessage(message)
            guard let target = ChatGuideGuideCardLocator.locateFirstGuideCard(in: [inserted]) else {
                return Output(target: nil, didInsert: false)
            }
            logger.info(
                "chat.guide.card.inserted thread=\(String(threadID.uuidString.prefix(8))) message=\(String(target.message.clientMessageID.uuidString.prefix(8))) member=\(thread.memberID.map(String.init) ?? "nil")",
                module: .general
            )
            return Output(target: target, didInsert: true)
        } catch {
            // 插入失败不阻塞会话页面，仅记录日志；调用方据此跳过科普问题生成
            logger.error(
                "新会话首条引导消息插入失败，thread=\(String(threadID.uuidString.prefix(8))), error=\(error.localizedDescription)",
                module: .general
            )
            return Output(target: nil, didInsert: false)
        }
    }

    private func healthDataAccessResult(memberID: Int?) async -> HealthDataAccessResult {
        guard let memberID else {
            return .noBinding(.appleHealth)
        }
        return await accessGate.checkAccess(for: .appleHealth, memberId: memberID)
    }

    nonisolated private static func logReason(for result: HealthDataAccessResult) -> String {
        switch result {
        case .granted:
            return "granted"
        case .noBinding:
            return "no_binding"
        case .authorizationRevoked:
            return "authorization_revoked"
        case .authorizationDenied:
            return "authorization_denied"
        case .partialAuthorization:
            return "partial_authorization"
        case .memberNotBound:
            return "member_not_bound"
        case .dataSourceNotAvailable:
            return "data_source_not_available"
        case .healthKitUnavailable:
            return "healthkit_unavailable"
        }
    }
}
