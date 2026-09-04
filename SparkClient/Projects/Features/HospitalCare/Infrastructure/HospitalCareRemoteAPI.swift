import Foundation

struct HospitalCareRemoteAPI: Sendable {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    func listHospitals(page: Int = 1, pageSize: Int = 20) async throws -> [HospitalPublicDTO] {
        let payload: HospitalCarePageDTO<HospitalPublicDTO> = try await get(
            name: "HospitalCare.Hospitals",
            path: "/api/v1/hospital-care/hospitals/",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ],
            serialKey: "hospital_care.hospitals"
        )
        return payload.items
    }

    func listDepartments(hospitalID: UUID) async throws -> [HospitalDepartmentPublicDTO] {
        let payload: HospitalCarePageDTO<HospitalDepartmentPublicDTO> = try await get(
            name: "HospitalCare.Departments",
            path: "/api/v1/hospital-care/hospitals/\(hospitalID.hospitalCarePathID)/departments/",
            serialKey: "hospital_care.departments.\(hospitalID.hospitalCarePathID)"
        )
        return payload.items
    }

    func listAgents(
        hospitalID: UUID,
        departmentID: UUID? = nil,
        keyword: String = "",
        page: Int = 1,
        pageSize: Int = 50
    ) async throws -> [HospitalAgentPublicDTO] {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        if let departmentID {
            queryItems.append(URLQueryItem(name: "department_id", value: departmentID.hospitalCarePathID))
        }
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            queryItems.append(URLQueryItem(name: "keyword", value: trimmed))
        }
        let payload: HospitalCarePageDTO<HospitalAgentPublicDTO> = try await get(
            name: "HospitalCare.Agents",
            path: "/api/v1/hospital-care/hospitals/\(hospitalID.hospitalCarePathID)/agents/",
            queryItems: queryItems,
            serialKey: "hospital_care.agents.\(hospitalID.hospitalCarePathID)"
        )
        return payload.items
    }

    func fetchAgent(agentID: UUID) async throws -> HospitalAgentPublicDTO {
        try await get(
            name: "HospitalCare.AgentDetail",
            path: "/api/v1/hospital-care/agents/\(agentID.hospitalCarePathID)/",
            serialKey: "hospital_care.agent.\(agentID.hospitalCarePathID)"
        )
    }

    /// CHAT-000058：按 agent_id + member_id 查询医生智能体唯一直连运行配置。
    /// 响应包含 endpoint/凭证/systemProvision，调用方不得写入日志或普通缓存。
    func fetchAgentRuntimeConfig(agentID: UUID, memberID: Int) async throws -> HospitalAgentRuntimeConfigDTO {
        try await get(
            name: "HospitalCare.AgentRuntimeConfig",
            path: "/api/v1/hospital-care/agents/\(agentID.hospitalCarePathID)/runtime-config/",
            queryItems: [URLQueryItem(name: "member_id", value: String(memberID))],
            serialKey: "hospital_care.agent.runtime_config.\(agentID.hospitalCarePathID).\(memberID)"
        )
    }

    func listConversations(memberID: Int, page: Int = 1, pageSize: Int = 100) async throws -> [HospitalConversationDTO] {
        let payload: HospitalCarePageDTO<HospitalConversationDTO> = try await get(
            name: "HospitalCare.Conversations",
            path: "/api/v1/hospital-care/conversations/",
            queryItems: [
                URLQueryItem(name: "member_id", value: String(memberID)),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ],
            serialKey: "hospital_care.conversations.\(memberID)"
        )
        return payload.items
    }

    /// 拉取当前账号全部医院会话（跨成员、自动翻页），用于登录/切换账号后回填本地 scope。
    func listAllConversations(pageSize: Int = 100) async throws -> [HospitalConversationDTO] {
        var page = 1
        var collected: [HospitalConversationDTO] = []
        while true {
            let payload: HospitalCarePageDTO<HospitalConversationDTO> = try await get(
                name: "HospitalCare.Conversations.All",
                path: "/api/v1/hospital-care/conversations/",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page_size", value: String(pageSize)),
                ],
                serialKey: "hospital_care.conversations.all"
            )
            collected.append(contentsOf: payload.items)
            let totalPages = payload.pagination?.totalPages ?? page
            if payload.items.count < pageSize || page >= totalPages {
                break
            }
            page += 1
        }
        return collected
    }

    /// 读取 Thread 的医院绑定 context；404 表示非医院会话返回 nil，其他错误照常抛出。
    /// memberID 非空时服务端一并校验成员归属；撤权时抛 403 MEMBER_ACCESS_DENIED。
    func fetchConversationContext(threadID: UUID, memberID: Int?) async throws -> HospitalConversationContextDTO? {
        var queryItems: [URLQueryItem] = []
        if let memberID {
            queryItems.append(URLQueryItem(name: "member_id", value: String(memberID)))
        }
        do {
            return try await get(
                name: "HospitalCare.ConversationContext",
                path: "/api/v1/hospital-care/conversations/\(threadID.hospitalCarePathID)/context/",
                queryItems: queryItems,
                serialKey: "hospital_care.conversation.context.\(threadID.hospitalCarePathID)"
            )
        } catch SparkNetworkError.httpError(let statusCode, _, _) where statusCode == 404 {
            return nil
        }
    }

    func pullHospitalKnowledge(
        knowledgeBaseID: UUID,
        cursor: String?,
        limit: Int
    ) async throws -> HospitalKnowledgePullPageDTO {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, cursor.isEmpty == false {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await get(
            name: "HospitalCare.KnowledgePull",
            path: "/api/v1/hospital-care/knowledge-bases/\(knowledgeBaseID.hospitalCarePathID)/sync/pull/",
            queryItems: queryItems,
            serialKey: "hospital_care.knowledge.pull.\(knowledgeBaseID.hospitalCarePathID)"
        )
    }

    func createConversation(agentID: UUID, memberID: Int) async throws -> HospitalCreateConversationResponseDTO {
        let body = try JSONEncoder.chatRemote.encode(
            HospitalCreateConversationRequestDTO(agentId: agentID, memberId: memberID)
        )
        let operation = CacheableSparkNetworkOperation(
            name: "HospitalCare.CreateConversation",
            apiName: "HospitalCareRemoteAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/hospital-care/conversations/",
                headers: ["Idempotency-Key": UUID().uuidString],
                body: .raw(body, contentType: "application/json"),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "hospital_care.conversation.create.\(agentID.hospitalCarePathID).\(memberID)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(
            HospitalCreateConversationResponseDTO.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
    }

    private func get<T: Decodable>(
        name: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        serialKey: String
    ) async throws -> T {
        let operation = CacheableSparkNetworkOperation(
            name: name,
            apiName: "HospitalCareRemoteAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: path,
                queryItems: queryItems.isEmpty ? nil : queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: serialKey,
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal
                )
            )
        )
        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(
            T.self,
            from: response,
            decoder: JSONDecoder.chatRemote
        )
    }
}

private extension UUID {
    /// Django `<uuid:...>` 路由只匹配小写 hex，iOS `uuidString` 默认大写会直接 404。
    var hospitalCarePathID: String { uuidString.lowercased() }
}

/// 供 UseCase 依赖注入与单元测试 mock 使用的只读接口面。
protocol HospitalCareRemoteServing: Sendable {
    func listHospitals(page: Int, pageSize: Int) async throws -> [HospitalPublicDTO]
    func listDepartments(hospitalID: UUID) async throws -> [HospitalDepartmentPublicDTO]
    func listAgents(
        hospitalID: UUID,
        departmentID: UUID?,
        keyword: String,
        page: Int,
        pageSize: Int
    ) async throws -> [HospitalAgentPublicDTO]
    func fetchAgent(agentID: UUID) async throws -> HospitalAgentPublicDTO
    /// CHAT-000058：按 agent_id + member_id 查询医生智能体专用直连运行配置。
    func fetchAgentRuntimeConfig(agentID: UUID, memberID: Int) async throws -> HospitalAgentRuntimeConfigDTO
    func listConversations(memberID: Int, page: Int, pageSize: Int) async throws -> [HospitalConversationDTO]
    func listAllConversations(pageSize: Int) async throws -> [HospitalConversationDTO]
    func createConversation(agentID: UUID, memberID: Int) async throws -> HospitalCreateConversationResponseDTO
    /// 拉取指定医院会话的上下文（医院、智能体、就诊人、能力、知识 Manifest）。
    /// 服务端该路由不校验成员归属；404 表示该 Thread 不是医院会话。
    /// memberID 非空时服务端一并校验成员归属；撤权时抛 403 MEMBER_ACCESS_DENIED。
    func fetchConversationContext(threadID: UUID, memberID: Int?) async throws -> HospitalConversationContextDTO?
    /// CHAT-000055：医院知识库只读增量拉取（cursor 分页 + tombstone）。
    func pullHospitalKnowledge(
        knowledgeBaseID: UUID,
        cursor: String?,
        limit: Int
    ) async throws -> HospitalKnowledgePullPageDTO
}

extension HospitalCareRemoteAPI: HospitalCareRemoteServing {}
