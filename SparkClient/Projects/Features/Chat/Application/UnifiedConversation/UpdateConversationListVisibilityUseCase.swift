import Foundation

/// CHAT-000057 D-011/D-012/Q8/Q9：医疗类会话「从消息列表移除」统一处理。
///
/// 严格语义：
/// - 只改变当前患者账号在消息列表中的可见性——不删除服务端 Thread、不删除消息/病历/审计记录、
///   不调用 deleteThreadUseCase、不写 ChatThread.isDeleted；
/// - 新患者可见消息成功落库后自动恢复（restoreOnVisibleMessage，幂等可重入）；
/// - 撤权/已删除 Thread 不得借「自动恢复」重新暴露；
/// - 账号退出、服务端撤权、Thread 真删除时定向清理。
struct UpdateConversationListVisibilityUseCase: Sendable {
    let store: ConversationListVisibilityPreferenceStore
    let manifestRepository: UnifiedConversationManifestRepository
    let logger: Logger

    nonisolated init(
        store: ConversationListVisibilityPreferenceStore,
        manifestRepository: UnifiedConversationManifestRepository,
        logger: Logger = ConsoleLogger()
    ) {
        self.store = store
        self.manifestRepository = manifestRepository
        self.logger = logger
    }

    /// 隐藏医疗会话（写入账号级偏好；失败时返回 false 供 UI 回滚卡片）。
    /// - Note: 医疗类型门禁由调用方（ViewModel 按 `isMedicalKind`）保证；此处只负责持久化。
    @discardableResult
    func hide(threadID: UUID, accountID: Int64, now: Date = Date()) -> Bool {
        store.setHidden(true, threadID: threadID, accountID: accountID, now: now)
        let persisted = store.preference(for: threadID, accountID: accountID)?.isHidden == true
        if persisted == false {
            logger.error(
                "chat.unified.visibility.hide_failed account=\(accountID) thread=\(threadID.uuidString.prefix(8))",
                module: .general
            )
        }
        return persisted
    }

    /// 患者主动恢复可见（重新展示已隐藏会话）。
    func restore(threadID: UUID, accountID: Int64) {
        store.setHidden(false, threadID: threadID, accountID: accountID)
    }

    /// CHAT-000057 22.3/22.5：新的患者可见消息成功落库后的幂等自动恢复。
    ///
    /// 前置条件由调用方保证：消息已完成持久化与可见性校验。
    /// 撤权/已删除 Thread 不恢复（31.6.6）；未隐藏的 Thread 调用为 no-op。
    func restoreOnVisibleMessage(threadID: UUID, accountID: Int64) {
        guard store.preference(for: threadID, accountID: accountID)?.isHidden == true else { return }
        let binding = manifestRepository.binding(for: threadID, accountID: accountID)
        guard binding?.isAccessRevoked != true else { return }
        store.setHidden(false, threadID: threadID, accountID: accountID)
        logger.info(
            "chat.unified.visibility.auto_restored account=\(accountID) thread=\(threadID.uuidString.prefix(8))",
            module: .general
        )
    }

    /// Thread 真删除/服务端撤权时的定向清理（21.3.5）。
    func cleanup(threadID: UUID, accountID: Int64) {
        store.remove(threadID: threadID, accountID: accountID)
    }

    /// 账号退出/切换清理。
    func clearAccount(_ accountID: Int64) {
        store.clearAccount(accountID)
    }
}
