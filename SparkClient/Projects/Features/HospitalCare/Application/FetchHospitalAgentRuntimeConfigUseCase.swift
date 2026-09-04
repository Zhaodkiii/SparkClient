import Foundation

/// CHAT-000058：医院医生智能体专用运行配置查询失败原因（按服务端稳定业务码映射，不依赖错误文案）。
enum HospitalAgentRuntimeConfigError: LocalizedError {
    /// 未登录或令牌失效（401 / AUTH_REQUIRED）。
    case unauthorized
    /// 当前账号无权访问该成员（403 / MEMBER_ACCESS_DENIED）。
    case memberAccessDenied
    /// 智能体不存在或已下架（404 / AGENT_NOT_FOUND）。
    case agentNotFound
    /// 智能体已停用（409 / AGENT_UNAVAILABLE）。
    case agentUnavailable
    /// 场景绑定无效（409 / AGENT_BINDING_INVALID）。
    case bindingInvalid
    /// 运行配置缺失或不完整（409 / RUNTIME_CONFIG_INVALID 或响应字段校验失败）。
    case runtimeConfigInvalid
    /// 请求参数非法（400 / PAYLOAD_INVALID）。
    case payloadInvalid
    /// 网络 / 超时 / 服务暂不可用（保留可重试入口）。
    case network

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "登录状态已失效，请重新登录后再试"
        case .memberAccessDenied:
            return "当前就诊人无法使用该服务，请切换就诊人后重试"
        case .agentNotFound:
            return "该医生智能体不存在或已下架"
        case .agentUnavailable:
            return "该医生智能体当前不可用"
        case .bindingInvalid, .runtimeConfigInvalid:
            return "该医生智能体服务配置已失效，请稍后再试"
        case .payloadInvalid:
            return "请求参数异常，请稍后再试"
        case .network:
            return "网络异常，请检查网络后重试"
        }
    }
}

/// CHAT-000058：按 `agent_id + member_id` 查询医院医生智能体专用直连运行配置。
///
/// - single-flight：同一 `account:hospital:member:agent` 复用进行中的请求；
/// - 响应身份字段（agent_id / member_id / hospital_id）与本地预期不一致时按配置失效处理；
/// - 错误按服务端稳定业务码映射为 ``HospitalAgentRuntimeConfigError``。
nonisolated final class FetchHospitalAgentRuntimeConfigUseCase: @unchecked Sendable {
    private let remoteAPI: any HospitalCareRemoteServing
    private let lock = NSLock()
    private var runningTasks: [String: Task<HospitalAgentRuntimeConfig, Error>] = [:]

    init(remoteAPI: any HospitalCareRemoteServing) {
        self.remoteAPI = remoteAPI
    }

    func execute(
        agentID: UUID,
        memberID: Int,
        hospitalID: UUID,
        accountID: Int64
    ) async throws -> HospitalAgentRuntimeConfig {
        let requestKey = "\(accountID):\(hospitalID.uuidString.lowercased()):\(memberID):\(agentID.uuidString.lowercased())"
        let task = claimRunningTask(forKey: requestKey) { [remoteAPI] in
            Task {
                let dto = try await remoteAPI.fetchAgentRuntimeConfig(agentID: agentID, memberID: memberID)
                guard let config = HospitalAgentRuntimeConfig.make(
                    from: dto,
                    expectedAgentID: agentID,
                    expectedMemberID: memberID,
                    expectedHospitalID: hospitalID
                ) else {
                    throw HospitalAgentRuntimeConfigError.runtimeConfigInvalid
                }
                return config
            }
        }
        defer { removeRunningTask(forKey: requestKey) }
        do {
            return try await task.value
        } catch {
            throw Self.mapError(error)
        }
    }

    /// single-flight：同一 key 复用进行中的任务（同步方法内持锁，避免跨 suspension point）。
    private func claimRunningTask(
        forKey key: String,
        make: () -> Task<HospitalAgentRuntimeConfig, Error>
    ) -> Task<HospitalAgentRuntimeConfig, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let running = runningTasks[key] {
            return running
        }
        let task = make()
        runningTasks[key] = task
        return task
    }

    private func removeRunningTask(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        runningTasks[key] = nil
    }

    /// 服务端业务码 → 类型化错误；不解析错误文案决定流程。
    static func mapError(_ error: Error) -> Error {
        if error is HospitalAgentRuntimeConfigError || error is CancellationError {
            return error
        }
        guard case SparkNetworkError.httpError(let statusCode, let backend, _) = error else {
            return HospitalAgentRuntimeConfigError.network
        }
        let codeText = backend?.msg.uppercased() ?? ""
        if codeText.contains("MEMBER_ACCESS_DENIED") { return HospitalAgentRuntimeConfigError.memberAccessDenied }
        if codeText.contains("AGENT_NOT_FOUND") { return HospitalAgentRuntimeConfigError.agentNotFound }
        if codeText.contains("AGENT_UNAVAILABLE") { return HospitalAgentRuntimeConfigError.agentUnavailable }
        if codeText.contains("AGENT_BINDING_INVALID") { return HospitalAgentRuntimeConfigError.bindingInvalid }
        if codeText.contains("RUNTIME_CONFIG_INVALID") { return HospitalAgentRuntimeConfigError.runtimeConfigInvalid }
        if codeText.contains("PAYLOAD_INVALID") { return HospitalAgentRuntimeConfigError.payloadInvalid }
        switch statusCode {
        case 401:
            return HospitalAgentRuntimeConfigError.unauthorized
        case 403:
            return HospitalAgentRuntimeConfigError.memberAccessDenied
        case 404:
            return HospitalAgentRuntimeConfigError.agentNotFound
        case 409:
            return HospitalAgentRuntimeConfigError.agentUnavailable
        default:
            return HospitalAgentRuntimeConfigError.network
        }
    }
}
