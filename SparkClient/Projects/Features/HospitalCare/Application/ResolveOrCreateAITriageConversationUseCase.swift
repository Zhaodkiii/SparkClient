import Foundation

/// 医院 Tab / 会话内「新建」：每次调用都向服务端创建新的 AI 导诊 Thread（不复用历史会话）。
nonisolated struct ResolveOrCreateAITriageConversationUseCase {
    let remoteAPI: any HospitalCareRemoteServing
    let scopeStore: HospitalConversationScopeStore
    let fetchTriageRuntimeConfig: FetchHospitalAITriageRuntimeConfigUseCase
    let runtimeConfigStore: HospitalAgentRuntimeConfigStore
    let chatRepository: any ChatRepository
    let chatStateStore: ChatStateStore
    let provenanceStore: ThreadCreationProvenanceStore

    func execute(
        hospitalID: UUID,
        memberID: Int,
        accountID: Int64
    ) async throws -> UUID {
        let configScope = HospitalAgentRuntimeConfigStore.Scope(
            accountID: accountID,
            hospitalID: hospitalID,
            memberID: memberID,
            agentID: hospitalID,
            isAITriage: true
        )

        if runtimeConfigStore.cachedConfig(for: configScope) == nil {
            let fetched = try await fetchTriageRuntimeConfig.execute(
                hospitalID: hospitalID,
                memberID: memberID,
                accountID: accountID
            )
            runtimeConfigStore.save(fetched, accountID: accountID)
        }

        // 每次进入导诊都新建会话；幂等仅由请求头 Idempotency-Key 保护，不按医院+成员复用。
        let created = try await remoteAPI.createAITriageConversation(hospitalID: hospitalID, memberID: memberID)

        if let remoteThread = created.thread {
            guard let thread = ChatSyncEngineDTOMapper.toDomainThread(remoteThread) else {
                throw HospitalConversationResolveError.threadMappingFailed
            }
            await chatRepository.upsertRemoteThreads([thread])
            guard await chatRepository.loadThread(id: thread.id) != nil else {
                throw HospitalConversationResolveError.threadMappingFailed
            }
        }

        scopeStore.remember(
            HospitalConversationScope(
                threadID: created.threadId,
                agentID: nil,
                memberID: memberID,
                hospitalID: hospitalID,
                isAITriage: true
            ),
            accountID: accountID
        )

        // 与医院医生会话一致：创建响应里的初始系统卡（医院介绍 + 导诊引导）交给 ChatView 入站落库。
        // 不依赖 thread DTO 是否齐全——threadId 已足够锚定；缺 thread 时仍登记消息，避免首屏无卡。
        let initialMessages = created.initialMessages.compactMap(ChatSyncEngineDTOMapper.toDomain)
        await MainActor.run {
            provenanceStore.remember(
                ThreadCreationProvenance(threadID: created.threadId, origin: .aiTriageFlow),
                accountID: accountID
            )
            if initialMessages.isEmpty == false {
                chatStateStore.rememberHospitalInitialMessages(initialMessages, for: created.threadId)
            }
            chatStateStore.markThreadAsNewlyCreated(created.threadId)
        }
        return created.threadId
    }
}
