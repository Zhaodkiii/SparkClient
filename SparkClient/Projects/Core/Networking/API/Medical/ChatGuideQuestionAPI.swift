import Foundation

/// 客户端「对话引导卡片科普问题」登记与点击统计 API（BACKOFFICE-CONVERSATION-000001 客户端侧）。
///
/// 接口均按后台异步 best-effort 调用，失败不阻断主流程：
/// - `register`：AI 成功生成并回写 guide block 后登记问题，返回 clientQuestionID → serverQuestionID 映射。
/// - `reportClick`：用户点击已登记的 AI 生成问题后，原子递增服务端 click_count。
struct SparkChatGuideQuestionAPI: @unchecked Sendable {
    /// 统一后端配置（网络引擎、鉴权、日志）。
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    /// 单条登记问题（与 `ChatGuideQuestion` 对齐，字段以 snake_case 上送）。
    nonisolated struct RegisterItem: Encodable, Sendable {
        let id: String
        let title: String
        let prompt: String
        let category: String
    }

    nonisolated struct RegisterRequest: Encodable, Sendable {
        let memberId: Int
        let questions: [RegisterItem]
    }

    nonisolated struct RegisterResponse: Decodable, Sendable {
        let registered: Int
        let failed: Int
        let items: [RegisteredItem]

        nonisolated struct RegisteredItem: Decodable, Sendable {
            let clientQuestionId: String
            let serverQuestionId: Int
        }
    }

    nonisolated struct ClickRequest: Encodable, Sendable {
        let serverQuestionId: Int
        let memberId: Int?
    }

    nonisolated struct ClickResponse: Decodable, Sendable {
        let accepted: Bool
        let serverQuestionId: Int
        let clickCount: Int?
    }

    /// 登记 AI 生成问题，返回 clientQuestionID → serverQuestionID 映射。
    func register(memberId: Int, items: [RegisterItem]) async throws -> [String: Int] {
        configuration.logger.info(
            "[CHATGUIDE-DEBUG][api] register start memberId=\(memberId) count=\(items.count) ids=\(items.map(\.id).joined(separator: ","))",
            module: .network
        )
        do {
            let response: RegisterResponse = try await write(
                method: .post,
                path: "/api/v1/medical/chat-guide/questions/register/",
                body: RegisterRequest(memberId: memberId, questions: items),
                serialKey: "medical.chat_guide_question.register.\(memberId)"
            )
            var mapping: [String: Int] = [:]
            for item in response.items {
                mapping[item.clientQuestionId] = item.serverQuestionId
            }
            configuration.logger.info(
                "[CHATGUIDE-DEBUG][api] register success registered=\(response.registered) failed=\(response.failed) mapping=\(mapping)",
                module: .network
            )
            return mapping
        } catch {
            configuration.logger.warning(
                "[CHATGUIDE-DEBUG][api] register error=\(error)",
                module: .network
            )
            throw error
        }
    }

    /// 上送点击统计。
    @discardableResult
    func reportClick(serverQuestionId: Int, memberId: Int? = nil) async throws -> ClickResponse {
        configuration.logger.info(
            "[CHATGUIDE-DEBUG][api] reportClick start serverQuestionId=\(serverQuestionId) memberId=\(memberId.map(String.init) ?? "nil")",
            module: .network
        )
        do {
            let response: ClickResponse = try await write(
                method: .post,
                path: "/api/v1/medical/chat-guide/questions/click/",
                body: ClickRequest(serverQuestionId: serverQuestionId, memberId: memberId),
                serialKey: "medical.chat_guide_question.click.\(serverQuestionId)"
            )
            configuration.logger.info(
                "[CHATGUIDE-DEBUG][api] reportClick success accepted=\(response.accepted) clickCount=\(response.clickCount.map(String.init) ?? "nil")",
                module: .network
            )
            return response
        } catch {
            configuration.logger.warning(
                "[CHATGUIDE-DEBUG][api] reportClick error=\(error)",
                module: .network
            )
            throw error
        }
    }

    private func write<T: Decodable, B: Encodable & Sendable>(
        method: SparkHTTPMethod,
        path: String,
        body: B,
        serialKey: String,
        responseType: T.Type = T.self
    ) async throws -> T {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.ChatGuideQuestion.\(method.rawValue).\(path)",
            apiName: "SparkChatGuideQuestionAPI",
            request: SparkNetworkRequest(
                method: method,
                path: path,
                body: .json(AnyEncodable(body)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: serialKey,
                    retryConfig: .default,
                    isIdempotent: method != .post,
                    queuePriority: .high
                )
            )
        )
        let response = try await configuration.execute(operation)
        let bodyText = String(data: response.data, encoding: .utf8) ?? "<non-utf8>"
        configuration.logger.info(
            "[CHATGUIDE-DEBUG][api] write response status=\(response.httpResponse.statusCode) path=\(path) body=\(bodyText.prefix(500))",
            module: .network
        )
        return try APIResponseDecoder.decodeWrappedData(responseType, from: response, decoder: .medicalAPI)
    }
}