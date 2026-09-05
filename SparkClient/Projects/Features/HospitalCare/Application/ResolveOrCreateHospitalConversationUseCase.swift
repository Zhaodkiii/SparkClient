import Foundation

/// CHAT-000058：医院会话创建后的 scope / 绑定校验失败。
enum HospitalConversationResolveError: LocalizedError, Equatable {
    /// 创建返回的 hospital_id / member_id / agent_id 与本地预期不一致。
    case scopeMismatch
    /// 创建返回的 binding_id / binding_version 与专用运行配置不一致（按配置失效处理）。
    case bindingMismatch
    /// 创建响应中的规范化 Thread 无法映射为本地 ChatThread。
    case threadMappingFailed

    var errorDescription: String? {
        switch self {
        case .scopeMismatch:
            return "院内会话信息校验失败，请返回名医列表后重试"
        case .bindingMismatch:
            return "院内会话运行配置校验失败，请返回名医列表后重试"
        case .threadMappingFailed:
            return "院内会话初始化失败，请返回名医列表后重试"
        }
    }
}

/// CHAT-000058 C-017/C-018：先取专用运行配置（成功才继续）→ 再创建/复用 Thread → 校验 scope。
/// 任一阶段失败都不创建/不打开可发送会话，不回退普通 AI。
nonisolated struct ResolveOrCreateHospitalConversationUseCase {
    let remoteAPI: any HospitalCareRemoteServing
    let scopeStore: HospitalConversationScopeStore
    let fetchRuntimeConfig: FetchHospitalAgentRuntimeConfigUseCase
    let runtimeConfigStore: HospitalAgentRuntimeConfigStore
    let chatRepository: any ChatRepository
    let chatStateStore: ChatStateStore

    func execute(
        agentID: UUID,
        memberID: Int,
        hospitalID: UUID,
        accountID: Int64,
        recentThreadID: UUID?
    ) async throws -> UUID {
        let configScope = HospitalAgentRuntimeConfigStore.Scope(
            accountID: accountID,
            hospitalID: hospitalID,
            memberID: memberID,
            agentID: agentID
        )

        // 1. 专用运行配置：内存/Keychain 命中可直接使用（后台校验由会话页负责）；
        //    未命中必须先成功查询（C-003：查询失败不创建 Thread、不打开会话）。
        let config: HospitalAgentRuntimeConfig
        if let cached = runtimeConfigStore.cachedConfig(for: configScope) {
            config = cached
        } else {
            let fetched = try await fetchRuntimeConfig.execute(
                agentID: agentID,
                memberID: memberID,
                hospitalID: hospitalID,
                accountID: accountID
            )
            runtimeConfigStore.save(fetched, accountID: accountID)
            config = fetched
        }

        // 2. 复用最近智能体 Thread 或创建新 Thread（客户端不提交 binding/model/endpoint 等字段）。
        // 线上问诊会话带 consultationID，不能被智能体路径复用或改写 scope。
        if let recentThreadID {
            let existing = scopeStore.scope(for: recentThreadID, accountID: accountID)
            if existing?.consultationID == nil {
                scopeStore.remember(
                    HospitalConversationScope(
                        threadID: recentThreadID,
                        agentID: agentID,
                        memberID: memberID,
                        hospitalID: hospitalID,
                        consultationID: existing?.consultationID,
                        consultNo: existing?.consultNo
                    ),
                    accountID: accountID
                )
                return recentThreadID
            }
        }
        let created = try await remoteAPI.createConversation(agentID: agentID, memberID: memberID)
        ConsoleLogger().debug(
            "CHAT-000061 create_response thread=\(created.threadId.uuidString.prefix(8)) has_thread=\(created.thread != nil) initial_messages=\(created.initialMessages.count)",
            module: .general
        )

        // 3. 校验返回 scope 与本地预期一致（C-017：不一致视为失败，不进入可发送页面）。
        let conversation = created.conversation
        guard conversation.agent.id == agentID else {
            throw HospitalConversationResolveError.scopeMismatch
        }
        if let returnedMemberID = conversation.memberId, returnedMemberID != memberID {
            throw HospitalConversationResolveError.scopeMismatch
        }
        if let returnedHospitalID = conversation.hospital?.id, returnedHospitalID != hospitalID {
            throw HospitalConversationResolveError.scopeMismatch
        }
        // C-018/Q19：服务端返回的固定绑定与专用配置不一致时按配置失效处理（旧服务端缺省字段不校验）。
        if let bindingID = conversation.bindingId,
           let bindingVersion = conversation.bindingVersion,
           bindingID != config.bindingID || bindingVersion != config.bindingVersion {
            runtimeConfigStore.delete(for: configScope)
            throw HospitalConversationResolveError.bindingMismatch
        }

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
                agentID: agentID,
                memberID: memberID,
                hospitalID: conversation.hospital?.id ?? hospitalID
            ),
            accountID: accountID
        )
        // 仅当创建响应带有规范化 Thread 时登记医院新建上下文；
        // 旧幂等快照缺少 thread 时按历史会话进入，由常规 pull 补齐。
        if created.thread != nil {
            let initialMessages = created.initialMessages.compactMap(ChatSyncEngineDTOMapper.toDomain)
            ConsoleLogger().debug(
                "CHAT-000061 initial_messages_mapped thread=\(created.threadId.uuidString.prefix(8)) raw=\(created.initialMessages.count) mapped=\(initialMessages.count)",
                module: .general
            )
            await MainActor.run {
                chatStateStore.rememberHospitalInitialMessages(initialMessages, for: created.threadId)
            }
        }
        return created.threadId
    }
}
