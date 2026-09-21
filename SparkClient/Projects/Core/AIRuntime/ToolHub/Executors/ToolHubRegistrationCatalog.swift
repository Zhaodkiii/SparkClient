import Foundation

private struct RegistrationToolErrorBody: Codable {
    let code: String
    let message: String
    let retryable: Bool
}

private struct RegistrationToolFailureBody: Codable {
    let ok: Bool
    let tool: String
    let error: RegistrationToolErrorBody
}

extension ToolHub {
    func runQueryRegistrationCatalog(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> ToolExecutionResult {
        guard let service = registrationCatalogService else {
            return registrationFailure(
                toolName: invocation.name,
                error: RegistrationCatalogServiceError.catalogUnavailable,
                arguments: invocation.arguments,
                shouldBypassModel: false
            )
        }
        let scope = invocation.arguments["scope"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard scope == "departments" || scope == "doctors" else {
            return registrationFailure(
                toolName: invocation.name,
                error: RegistrationCatalogServiceError.catalogUnavailable,
                code: "REGISTRATION_INVALID_SCOPE",
                message: "scope 必须是 departments 或 doctors。",
                arguments: invocation.arguments,
                shouldBypassModel: false
            )
        }
        let departmentID = UUID(uuidString: invocation.arguments["department_id"] ?? "")
        let limit = Int(invocation.arguments["limit"] ?? "20") ?? 20
        do {
            let result = try await service.query(
                scope: scope,
                departmentID: departmentID,
                keyword: invocation.arguments["keyword"],
                limit: limit
            )
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: registrationJSON(result),
                sensitive: false,
                shouldBypassModel: false,
                arguments: invocation.arguments
            )
        } catch {
            return registrationFailure(
                toolName: invocation.name,
                error: error,
                arguments: invocation.arguments,
                shouldBypassModel: false
            )
        }
    }

    func runShowRegistrationRecommendation(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> ToolExecutionResult {
        guard let service = registrationCatalogService,
              let departmentID = UUID(uuidString: invocation.arguments["department_id"] ?? "") else {
            return registrationFailure(
                toolName: invocation.name,
                error: RegistrationCatalogServiceError.departmentNotFound,
                arguments: invocation.arguments,
                shouldBypassModel: false
            )
        }
        let reason = invocation.arguments["reason_summary"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard reason.isEmpty == false else {
            return registrationFailure(
                toolName: invocation.name,
                error: RegistrationCatalogServiceError.catalogUnavailable,
                code: "REGISTRATION_REASON_REQUIRED",
                message: "reason_summary 不能为空。",
                arguments: invocation.arguments,
                shouldBypassModel: false
            )
        }
        let agentID = UUID(uuidString: invocation.arguments["agent_id"] ?? "")
        do {
            let validated = try await service.validate(departmentID: departmentID, agentID: agentID)
            let payload = ChatRegistrationRecommendationCardPayload(
                hospitalID: validated.hospital.id,
                hospitalName: validated.hospital.name,
                departmentID: validated.department.id,
                departmentName: validated.department.name,
                agentID: validated.doctor?.agentID,
                doctorID: validated.doctor?.doctorID,
                doctorName: validated.doctor?.name,
                doctorTitle: validated.doctor?.title,
                doctorAvatarURL: validated.doctor?.avatarURL,
                reasonSummary: reason
            )
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "挂号推荐卡片已插入消息。",
                sensitive: false,
                shouldBypassModel: true,
                arguments: invocation.arguments,
                sideEffects: [.registrationRecommendation(payload)]
            )
        } catch {
            return registrationFailure(
                toolName: invocation.name,
                error: error,
                arguments: invocation.arguments,
                shouldBypassModel: false
            )
        }
    }

    private func registrationJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder.chatRemote.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":{\"code\":\"REGISTRATION_ENCODING_FAILED\"}}"
        }
        return text
    }

    private func registrationFailure(
        toolName: String,
        error: Error,
        code: String? = nil,
        message: String? = nil,
        arguments: [String: String],
        shouldBypassModel: Bool
    ) -> ToolExecutionResult {
        let serviceError = error as? RegistrationCatalogServiceError
        let resolvedCode = code ?? serviceError?.code ?? "REGISTRATION_CATALOG_UNAVAILABLE"
        let resolvedMessage = message ?? serviceError?.localizedDescription ?? "暂时无法获取挂号目录。"
        let output = registrationJSON(RegistrationToolFailureBody(
            ok: false,
            tool: toolName,
            error: RegistrationToolErrorBody(
                code: resolvedCode,
                message: resolvedMessage,
                retryable: resolvedCode == "REGISTRATION_CATALOG_UNAVAILABLE"
            )
        ))
        return ToolExecutionResult(
            toolName: toolName,
            outputText: output,
            sensitive: false,
            shouldBypassModel: shouldBypassModel,
            arguments: arguments
        )
    }
}
