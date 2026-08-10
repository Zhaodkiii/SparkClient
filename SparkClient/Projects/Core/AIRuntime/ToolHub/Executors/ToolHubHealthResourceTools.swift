import Foundation

extension ToolHub {
    private static let healthResourceTypeEnumValues: [String] = HealthResourceType.allCases.map(\.rawValue)

    func healthResourceTypeProperty() -> AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: "string",
            description: td("tool.param.health_resource_type_enum"),
            enumValues: Self.healthResourceTypeEnumValues
        )
    }

    func healthResourceTypesProperty() -> AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: "array",
            description: td("tool.param.health_resource_types_filter"),
            arrayItems: healthResourceTypeProperty()
        )
    }

    func parseHealthResourceTypeFilter(from arguments: [String: String]) -> HealthResourceListTypeFilter.Parsed {
        HealthResourceListTypeFilter.parse(arguments: arguments)
    }

    func appendUnrecognizedHealthResourceTypesNotice(
        to output: String,
        unrecognized: [String]
    ) -> String {
        guard unrecognized.isEmpty == false else { return output }
        let list = unrecognized.joined(separator: ", ")
        return output + "\n\n【系统】未识别的健康资料类型已忽略：\(list)。可用类型见 resource_types 参数说明。"
    }

    func runListMemberHealthSources(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> ToolExecutionResult {
        guard let scope = await resolveHealthResourceMemberScope(invocation: invocation, context: context) else {
            return scopeDeniedResult(tool: .listMemberHealthSources)
        }
        let memberID = scope

        let typeFilter = parseHealthResourceTypeFilter(from: invocation.arguments)
        let keyword = invocation.arguments["keyword"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let startDate = invocation.arguments["start_date"]
        let endDate = invocation.arguments["end_date"]
        let limit = Int(invocation.arguments["limit"] ?? "") ?? 20

        let listResult = await healthResourceToolService.listSources(
            query: HealthResourceListQuery(
                resourceTypes: typeFilter.resourceTypes,
                keyword: keyword?.isEmpty == true ? nil : keyword,
                startDate: startDate,
                endDate: endDate,
                limit: limit
            ),
            memberID: memberID
        )
        guard case .success(let listed) = listResult else {
            return healthResourceErrorResult(
                tool: .listMemberHealthSources,
                code: "load_failed",
                message: L10n.text("chat.ask_report.tool.error.load_failed")
            )
        }

        let payload = ListMemberHealthSourcesResponse(
            version: 1,
            memberId: memberID,
            query: ListMemberHealthSourcesQuery(
                keyword: keyword?.isEmpty == true ? nil : keyword,
                resourceTypes: typeFilter.resourceTypes,
                startDate: startDate,
                endDate: endDate,
                limit: limit
            ),
            candidates: listed.candidates,
            truncated: listed.truncated
        )

        let baseOutput = encodeJSON(payload) ?? "{}"

        if HealthResourceToolOrchestration.requiresUserSelection(candidates: listed.candidates) {
            guard let threadID = context.threadID,
                  let coordinator = toolInteractionCoordinator else {
                return ToolExecutionResult(
                    toolName: SparkToolName.listMemberHealthSources,
                    outputText: appendUnrecognizedHealthResourceTypesNotice(
                        to: HealthResourceToolOrchestration.appendMemberScopeNotice(
                            to: baseOutput + "\n\n【系统】当前界面无法展示健康资料候选选择，请根据 JSON 候选列表继续。",
                            memberID: memberID
                        ),
                        unrecognized: typeFilter.unrecognized
                    ),
                    sensitive: true,
                    shouldBypassModel: true,
                    resolvedMemberID: memberID,
                    arguments: invocation.arguments
                )
            }

            let prompt = HealthResourceToolCandidatePrompt(
                threadID: threadID,
                candidates: listed.candidates,
                maxSelectable: HealthResourceSendValidator.maxRefs
            )
            let selectionResult = await coordinator.requestHealthResourceCandidateSelection(
                prompt: prompt,
                toolCallID: context.pendingToolCallID
            )
            switch selectionResult {
            case .success(let selected):
                let outputText = appendUnrecognizedHealthResourceTypesNotice(
                    to: HealthResourceToolOrchestration.makeConfirmedToolOutput(
                        memberID: memberID,
                        query: payload.query,
                        selected: selected,
                        encodeJSON: { encodeJSON($0) }
                    ),
                    unrecognized: typeFilter.unrecognized
                )
                return ToolExecutionResult(
                    toolName: SparkToolName.listMemberHealthSources,
                    outputText: outputText,
                    sensitive: true,
                    shouldBypassModel: true,
                    resolvedMemberID: memberID,
                    arguments: invocation.arguments
                )
            case .cancelled, .conflict:
                return ToolExecutionResult(
                    toolName: SparkToolName.listMemberHealthSources,
                    outputText: "【系统】用户取消或未确认健康资料候选。请继续当前对话，必要时用自然语言请用户说明要分析的资料。",
                    sensitive: true,
                    shouldBypassModel: true,
                    isAwaitingUserInput: true,
                    arguments: invocation.arguments
                )
            }
        }

        var outputText = appendUnrecognizedHealthResourceTypesNotice(
            to: HealthResourceToolOrchestration.appendMemberScopeNotice(to: baseOutput, memberID: memberID),
            unrecognized: typeFilter.unrecognized
        )
        if listed.candidates.count == 1 {
            outputText += "\n\n【系统】检索结果唯一，无需用户确认。请用 get_health_resource_context 一次传入 references（含该条 resource_type+resource_id）获取解读正文（勿调用 get_health_resource_reference）。"
        }

        return ToolExecutionResult(
            toolName: SparkToolName.listMemberHealthSources,
            outputText: outputText,
            sensitive: true,
            shouldBypassModel: true,
            resolvedMemberID: memberID,
            arguments: invocation.arguments
        )
    }

    func runGetHealthResourceReference(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> ToolExecutionResult {
        guard let scope = await resolveHealthResourceMemberScope(invocation: invocation, context: context) else {
            return scopeDeniedResult(tool: .getHealthResourceReference)
        }
        guard let resourceType = invocation.arguments["resource_type"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              resourceType.isEmpty == false,
              let type = HealthResourceType(rawValue: resourceType),
              let resourceID = Int(invocation.arguments["resource_id"] ?? "") else {
            return healthResourceErrorResult(
                tool: .getHealthResourceReference,
                code: "invalid_args",
                message: L10n.text("chat.ask_report.error.invalid_reference")
            )
        }

        let identity = HealthResourceIdentity(type: type, resourceID: resourceID, memberID: scope)
        let validation = await healthResourceToolService.validateReference(identity)
        guard case .success(let summary) = validation,
              summary.status == .loaded || summary.status == .idle else {
            let payload = GetHealthResourceReferenceResponse(
                version: 1,
                reference: nil,
                resolveStatus: "not_found",
                displayTitle: nil,
                displaySubtitle: nil
            )
            return ToolExecutionResult(
                toolName: SparkToolName.getHealthResourceReference,
                outputText: encodeJSON(payload) ?? "{}",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let payload = GetHealthResourceReferenceResponse(
            version: 1,
            reference: HealthResourceToolReferenceDTO(
                resourceType: resourceType,
                resourceId: resourceID,
                memberId: scope
            ),
            resolveStatus: "ok",
            displayTitle: summary.title,
            displaySubtitle: [summary.dateText, summary.organizationText, summary.summaryText]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .joined(separator: " · ")
        )

        return ToolExecutionResult(
            toolName: SparkToolName.getHealthResourceReference,
            outputText: encodeJSON(payload) ?? "{}",
            sensitive: true,
            shouldBypassModel: true,
            sideEffects: [
                .healthResourceReference(
                    resourceType: resourceType,
                    resourceID: resourceID,
                    memberID: scope
                )
            ]
        )
    }

    func runGetHealthResourceContext(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> ToolExecutionResult {
        guard let scope = await resolveHealthResourceMemberScope(invocation: invocation, context: context) else {
            return scopeDeniedResult(tool: .getHealthResourceContext)
        }
        guard let identities = HealthResourceContextReferenceParser.identities(
            from: invocation.arguments,
            scopeMemberID: scope
        ), identities.isEmpty == false else {
            return healthResourceErrorResult(
                tool: .getHealthResourceContext,
                code: "invalid_args",
                message: L10n.text("chat.ask_report.error.invalid_reference")
            )
        }

        let topic = invocation.arguments["topic"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTopic = topic?.isEmpty == true ? nil : topic

        if identities.count == 1 {
            return await runGetHealthResourceContextSingle(
                identity: identities[0],
                memberID: scope,
                topic: normalizedTopic
            )
        }

        return await runGetHealthResourceContextBatch(
            identities: identities,
            memberID: scope,
            topic: normalizedTopic
        )
    }

    private func runGetHealthResourceContextSingle(
        identity: HealthResourceIdentity,
        memberID: Int,
        topic: String?
    ) async -> ToolExecutionResult {
        let resolved = await healthResourceToolService.resolveContext(identity, topic: topic)
        guard case .success(let context) = resolved, context.contextText.isEmpty == false else {
            return healthResourceErrorResult(
                tool: .getHealthResourceContext,
                code: "context_empty",
                message: L10n.text("chat.ask_report.tool.error.context_empty")
            )
        }

        let payload = GetHealthResourceContextResponse(
            version: 1,
            reference: HealthResourceToolReferenceDTO(
                resourceType: identity.resourceType,
                resourceId: identity.resourceID,
                memberId: identity.memberID
            ),
            contextText: context.contextText,
            topic: topic
        )

        let json = encodeJSON(payload) ?? "{}"
        let outputText = HealthResourceToolOrchestration.memberScopeNotice(memberID: memberID) + "\n" + json

        return ToolExecutionResult(
            toolName: SparkToolName.getHealthResourceContext,
            outputText: outputText,
            sensitive: true,
            shouldBypassModel: true,
            resolvedMemberID: memberID,
            sideEffects: [
                .healthResourceReference(
                    resourceType: identity.resourceType,
                    resourceID: identity.resourceID,
                    memberID: memberID
                )
            ]
        )
    }

    private func runGetHealthResourceContextBatch(
        identities: [HealthResourceIdentity],
        memberID: Int,
        topic: String?
    ) async -> ToolExecutionResult {
        let resolved = await healthResourceToolService.resolveContexts(identities, memberID: memberID, topic: topic)
        guard case .success(let batch) = resolved else {
            let code: String
            let message: String
            if case .failure(let error) = resolved {
                switch error {
                case .insufficientContent:
                    code = "context_empty"
                    message = L10n.text("chat.ask_report.tool.error.context_empty")
                case .forbidden:
                    code = "member_scope_denied"
                    message = L10n.text("chat.ask_report.tool.error.member_scope")
                case .invalidType:
                    code = "invalid_args"
                    message = L10n.text("chat.ask_report.error.invalid_reference")
                default:
                    code = "load_failed"
                    message = L10n.text("chat.ask_report.tool.error.load_failed")
                }
            } else {
                code = "context_empty"
                message = L10n.text("chat.ask_report.tool.error.context_empty")
            }
            return healthResourceErrorResult(tool: .getHealthResourceContext, code: code, message: message)
        }

        let payload = batch
        let json = encodeJSON(payload) ?? "{}"
        let batchNotice = """
        【系统】已一次性返回 \(batch.contexts.filter { $0.resolveStatus == "ok" }.count) 份资料解读上下文（version=2）。请优先阅读 combined_context_text 做对比分析，勿对同一批资料重复调用本工具。
        """
        let outputText = HealthResourceToolOrchestration.memberScopeNotice(memberID: memberID)
            + "\n"
            + batchNotice
            + "\n"
            + json

        let sideEffects = batch.contexts.compactMap { item -> ToolSideEffect? in
            guard item.resolveStatus == "ok" else { return nil }
            return .healthResourceReference(
                resourceType: item.reference.resourceType,
                resourceID: item.reference.resourceId,
                memberID: item.reference.memberId ?? memberID
            )
        }

        return ToolExecutionResult(
            toolName: SparkToolName.getHealthResourceContext,
            outputText: outputText,
            sensitive: true,
            shouldBypassModel: true,
            resolvedMemberID: memberID,
            sideEffects: sideEffects
        )
    }

    // MARK: - Scope

    private func resolveHealthResourceMemberScope(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> Int? {
        if let explicit = invocation.arguments["member_id"], let explicitID = Int(explicit), explicitID > 0 {
            if let bound = context.memberID, bound > 0, explicitID != bound {
                return nil
            }
            return explicitID
        }
        if let fromReferences = HealthResourceContextReferenceParser.scopeMemberID(
            fromReferencesJSON: invocation.arguments["references"]
        ) {
            if let bound = context.memberID, bound > 0, fromReferences != bound {
                return nil
            }
            return fromReferences
        }
        if let bound = context.memberID, bound > 0 {
            return bound
        }
        if let target = await resolveTargetMemberID(invocation: invocation, context: context), target > 0 {
            return target
        }
        if let selected = await awaitMemberSelection(
            invocation: invocation,
            context: context,
            reason: "health_resource_tools"
        ) {
            return selected
        }
        return nil
    }

    private func scopeDeniedResult(tool: SparkToolName) -> ToolExecutionResult {
        healthResourceErrorResult(
            tool: tool,
            code: "member_scope_denied",
            message: L10n.text("chat.ask_report.tool.error.member_scope")
        )
    }

    private func healthResourceErrorResult(
        tool: SparkToolName,
        code: String,
        message: String
    ) -> ToolExecutionResult {
        let payload = HealthResourceToolErrorResponse(version: 1, error: code, message: message)
        return ToolExecutionResult(
            toolName: tool,
            outputText: encodeJSON(payload) ?? message,
            sensitive: false,
            shouldBypassModel: true
        )
    }
}
