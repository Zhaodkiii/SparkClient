import Foundation

/// CHAT-000029 3.1：新建对话只负责本地 thread 创建（含前置解析好的初始 memberID）。
///
/// 默认绑定成员在调用方（新建对话编排层）解析后通过 `memberID` 传入；
/// 首条 system 引导卡片改由 `EnsureChatGuideSystemMessageUseCase`
/// 在进入会话页面后幂等插入；thread 元数据由 ChatSyncSupervisor 后台推送，
/// 均不阻塞本用例返回。
struct CreateThreadUseCase: Sendable {
    let repository: any ChatRepository
    let aiConfigCenter: AIConfigCenter
    let logger: Logger

    init(
        repository: any ChatRepository,
        aiConfigCenter: AIConfigCenter,
        logger: Logger = ConsoleLogger()
    ) {
        self.repository = repository
        self.aiConfigCenter = aiConfigCenter
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
        logger.info(
            "新会话本地创建完成，thread=\(String(thread.id.uuidString.prefix(8))) member=\(memberID.map(String.init) ?? "nil")",
            module: .general
        )
        return thread
    }
}
