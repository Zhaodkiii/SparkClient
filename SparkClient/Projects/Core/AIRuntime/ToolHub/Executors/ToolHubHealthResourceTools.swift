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

    func runListMemberHealthSources(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> ToolExecutionResult {
        guard let scope = await resolveHealthResourceMemberScope(invocation: invocation, context: context) else {
            return scopeDeniedResult(tool: .listMemberHealthSources)
        }
        let memberID = scope

        let resourceType = invocation.arguments["resource_type"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyword = invocation.arguments["keyword"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let startDate = invocation.arguments["start_date"]
        let endDate = invocation.arguments["end_date"]
        let limit = Int(invocation.arguments["limit"] ?? "") ?? 20

        let data: SparkMedicalSyncAPI.RemoteMemberCompleteData
        do {
            data = try await medicalQueryAPI.fetchMemberCompleteData(memberID: memberID)
        } catch {
            return healthResourceErrorResult(
                tool: .listMemberHealthSources,
                code: "load_failed",
                message: L10n.text("chat.ask_report.tool.error.load_failed")
            )
        }

        let listed = ChatHealthResourceSourceLister.list(
            data: data,
            resourceType: resourceType?.isEmpty == true ? nil : resourceType,
            keyword: keyword?.isEmpty == true ? nil : keyword,
            startDate: startDate,
            endDate: endDate,
            limit: limit
        )

        let payload = ListMemberHealthSourcesResponse(
            version: 1,
            memberID: memberID,
            query: ListMemberHealthSourcesQuery(
                keyword: keyword?.isEmpty == true ? nil : keyword,
                resourceType: resourceType?.isEmpty == true ? nil : resourceType,
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
                    outputText: HealthResourceToolOrchestration.appendMemberScopeNotice(
                        to: baseOutput + "\n\n【系统】当前界面无法展示健康资料候选选择，请根据 JSON 候选列表继续。",
                        memberID: memberID
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
            let selectionResult = await coordinator.requestHealthResourceCandidateSelection(prompt: prompt)
            switch selectionResult {
            case .success(let selected):
                let outputText = HealthResourceToolOrchestration.makeConfirmedToolOutput(
                    memberID: memberID,
                    query: payload.query,
                    selected: selected,
                    encodeJSON: { encodeJSON($0) }
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

        var outputText = HealthResourceToolOrchestration.appendMemberScopeNotice(to: baseOutput, memberID: memberID)
        if listed.candidates.count == 1 {
            outputText += "\n\n【系统】检索结果唯一，无需用户确认。请对该 resource 仅调用 get_health_resource_context 获取解读正文（勿调用 get_health_resource_reference）。"
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

        let ref = HealthResourceRef(
            type: type,
            resourceID: resourceID,
            memberID: scope,
            displayTitle: "",
            displaySubtitle: ""
        )

        let data = try? await medicalQueryAPI.fetchMemberCompleteData(memberID: scope)
        let recordService = HealthResourceRecordService(medicalQueryAPI: medicalQueryAPI)
        let summary = await recordService.cardSummary(
            for: ref,
            refIndex: 1,
            totalRefs: 1,
            cachedCompleteData: data
        )

        guard summary.status == .loaded || summary.status == .idle else {
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
                resourceID: resourceID,
                memberID: scope
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
        guard let resourceType = invocation.arguments["resource_type"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              resourceType.isEmpty == false,
              let type = HealthResourceType(rawValue: resourceType),
              let resourceID = Int(invocation.arguments["resource_id"] ?? "") else {
            return healthResourceErrorResult(
                tool: .getHealthResourceContext,
                code: "invalid_args",
                message: L10n.text("chat.ask_report.error.invalid_reference")
            )
        }

        let topic = invocation.arguments["topic"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = HealthResourceRef(
            type: type,
            resourceID: resourceID,
            memberID: scope,
            displayTitle: "",
            displaySubtitle: ""
        )

        let cached = try? await medicalQueryAPI.fetchMemberCompleteData(memberID: scope)
        let contextText = await HealthResourceContextResolver(medicalQueryAPI: medicalQueryAPI)
            .resolveContextText(refs: [ref], memberID: scope, cachedCompleteData: cached)

        guard contextText.isEmpty == false else {
            return healthResourceErrorResult(
                tool: .getHealthResourceContext,
                code: "context_empty",
                message: L10n.text("chat.ask_report.tool.error.context_empty")
            )
        }

        let payload = GetHealthResourceContextResponse(
            version: 1,
            reference: HealthResourceToolReferenceDTO(
                resourceType: resourceType,
                resourceID: resourceID,
                memberID: scope
            ),
            contextText: contextText,
            topic: topic?.isEmpty == true ? nil : topic
        )

        let json = encodeJSON(payload) ?? "{}"
        let outputText = HealthResourceToolOrchestration.memberScopeNotice(memberID: scope) + "\n" + json

        return ToolExecutionResult(
            toolName: SparkToolName.getHealthResourceContext,
            outputText: outputText,
            sensitive: true,
            shouldBypassModel: true,
            resolvedMemberID: scope,
            sideEffects: [
                .healthResourceReference(
                    resourceType: resourceType,
                    resourceID: resourceID,
                    memberID: scope
                )
            ]
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
