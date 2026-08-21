import Foundation

struct CreateThreadUseCase: Sendable {
    let repository: any ChatRepository
    let aiConfigCenter: AIConfigCenter
    /// 引导卡片数据聚合器；nil 时不插入首条系统引导消息（测试 / 访客链路）。
    let guideCardBuilder: ChatGuideCardPayloadBuilder?
    /// 读取 composer 启动偏好；nil 时视为默认绑定成员关闭。
    let aiSettingsRepository: (any AISettingsRepository)?
    let logger: Logger

    init(
        repository: any ChatRepository,
        aiConfigCenter: AIConfigCenter,
        guideCardBuilder: ChatGuideCardPayloadBuilder? = nil,
        aiSettingsRepository: (any AISettingsRepository)? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.aiConfigCenter = aiConfigCenter
        self.guideCardBuilder = guideCardBuilder
        self.aiSettingsRepository = aiSettingsRepository
        self.logger = logger
    }

    func execute(memberID: Int? = nil, title: String) async -> ChatThread {
        let snapshot = await aiConfigCenter.currentSnapshot()
        let thread = await repository.createThread(
            memberID: memberID,
            title: title,
            imageDeliveryModeRaw: snapshot.defaultThreadImageDeliveryModeRaw,
            rolePrompt: ""
        )
        await appendGuideMessageIfNeeded(thread: thread, memberID: memberID)
        return thread
    }

    /// thread 创建成功后插入首条 system 引导消息：
    /// - 幂等：thread 已存在引导卡片时不补插第二条；
    /// - 失败兜底：本地写入失败仅记录日志，仍返回 thread（允许进入空会话）。
    private func appendGuideMessageIfNeeded(thread: ChatThread, memberID: Int?) async {
        guard let guideCardBuilder else { return }
        do {
            let existing = await repository.loadMessages(threadID: thread.id, limit: 50, before: nil)
            let alreadyHasGuide = existing.contains { message in
                message.role == .system && message.blocks.contains { $0.kind == .chatGuideCard }
            }
            guard alreadyHasGuide == false else { return }

            let defaultMemberBindingEnabled = await resolveDefaultMemberBindingEnabled()
            let payload = await guideCardBuilder.build(
                memberID: memberID,
                defaultMemberBindingEnabled: defaultMemberBindingEnabled
            )
            let message = ChatGuideSystemMessageFactory.make(threadID: thread.id, payload: payload)
            _ = try await repository.appendMessage(message)
            logger.info(
                "新会话首条引导消息已插入，thread=\(String(thread.id.uuidString.prefix(8)))",
                module: .general
            )
        } catch {
            logger.error(
                "新会话首条引导消息插入失败，thread=\(String(thread.id.uuidString.prefix(8))), error=\(error.localizedDescription)",
                module: .general
            )
        }
    }

    private func resolveDefaultMemberBindingEnabled() async -> Bool {
        guard let aiSettingsRepository else { return false }
        let snapshot = await aiSettingsRepository.loadSnapshot()
        return snapshot.chatComposerStartupPreferences.memberProfileEnabled
    }
}
