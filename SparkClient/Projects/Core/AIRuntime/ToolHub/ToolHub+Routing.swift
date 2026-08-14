import Foundation

// ToolHub extension: slash/model entry routing, invocation parsing, and execute dispatcher.

extension ToolHub {
    /// 显式调试命令路由：`/audit_tools` 与 `/tool ...`。
    func runIfNeeded(
        userInput: String,
        memberID: Int?,
        allowedToolNames: Set<String>? = nil,
        threadID: UUID? = nil
    ) async -> ToolHubResult {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return .none }
        logger.debug(
            "工具路由检查开始，member=\(shortID(memberID)), inputLength=\(trimmed.count)",
            module: .aiConfig
        )

        if trimmed == "/audit_tools" {
            logger.info("工具路由命中 /audit_tools", module: .aiConfig)
            return await handleAuditTools()
        }

        let invocation = parseToolInvocation(from: trimmed)
        guard let invocation else {
            logger.debug("工具路由未命中，转入 AI 推理", module: .aiConfig)
            return .none
        }
        if let allowedToolNames,
           allowedToolNames.map(Self.normalizeToolName).contains(Self.normalizeToolName(invocation.name)) == false {
            logger.info("工具路由命中但不在当前允许列表内，tool=\(invocation.name)", module: .aiConfig)
            return .none
        }

        let context = ToolExecutionContext(memberID: memberID, locale: .current, threadID: threadID)
        let result = await execute(invocation: invocation, context: context)
        await appendAudit(invocation: invocation, context: context, result: result)
        return .executed(result)
    }

    private static func normalizeToolName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 执行模型返回的 tool_call，并写入统一审计。
    func executeToolCall(
        name: String,
        arguments: String,
        memberID: Int?,
        threadID: UUID? = nil,
        assistantMessageClientID: UUID? = nil,
        pendingToolCallID: String? = nil,
        pendingResumeMessages: [AIRuntimeMessage] = [],
        providerCompany: String? = nil,
        modelName: String? = nil,
        endpoint: String? = nil,
        privacyPolicyURL: URL? = nil
    ) async -> ToolExecutionResult {
        let invocation = ToolInvocation(name: name, arguments: parseArguments(arguments))
        let context = ToolExecutionContext(
            memberID: memberID,
            locale: .current,
            assistantMessageClientID: assistantMessageClientID,
            threadID: threadID,
            pendingToolCallID: pendingToolCallID,
            pendingResumeMessages: pendingResumeMessages,
            providerCompany: providerCompany,
            modelName: modelName,
            endpoint: endpoint,
            privacyPolicyURL: privacyPolicyURL
        )
        let rawResult = await execute(invocation: invocation, context: context)
        let result = await applyModelEgressConsentIfNeeded(
            invocation: invocation,
            context: context,
            result: rawResult
        )
            .withToolCallID(pendingToolCallID)
            .withAnchorToolCallID(pendingToolCallID)
            .withInvocationArgumentsIfMissing(invocation.arguments)
        await appendAudit(invocation: invocation, context: context, result: result)
        return result
    }

    /// 将用户输入解析为显式调试命令：`/tool list` 与 `/tool <name> <args>`。
    func parseToolInvocation(from input: String) -> ToolInvocation? {
        if input == "/tool list" {
            return ToolInvocation(name: "tool_list", arguments: [:])
        }

        if input.hasPrefix("/tool ") {
            let remainder = String(input.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard remainder.isEmpty == false else { return nil }
            let components = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let first = components.first else { return nil }
            let name = String(first)
            var arguments: [String: String] = [:]
            if components.count > 1 {
                arguments = parseArguments(String(components[1]))
            }
            return ToolInvocation(name: name, arguments: arguments)
        }
        return nil
    }

    /// 将模型返回的 JSON 参数展平：`{"coordinate":{"latitude":1,"longitude":2}}` → `coordinate.latitude` / `coordinate.longitude`；数组序列化为 JSON 字符串。
    func flattenJSONObject(_ object: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case is NSNull:
                continue
            case let dict as [String: Any]:
                let inner = flattenJSONObject(dict)
                for (innerKey, innerVal) in inner {
                    out["\(key).\(innerKey)"] = innerVal
                }
            case let arr as [Any]:
                if JSONSerialization.isValidJSONObject(arr),
                   let data = try? JSONSerialization.data(withJSONObject: arr, options: []),
                   let string = String(data: data, encoding: .utf8) {
                    out[key] = string
                } else {
                    out[key] = String(describing: value)
                }
            case let string as String:
                out[key] = string
            case let number as NSNumber:
                out[key] = number.stringValue
            case let bool as Bool:
                out[key] = bool ? "true" : "false"
            default:
                out[key] = String(describing: value)
            }
        }
        return out
    }

    /// 参数字符串：JSON 对象（嵌套 object 展平为 `a.b`）、`key=value` 空格分隔；否则填入 query/content 等默认键。
    func parseArguments(_ raw: String) -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [:] }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return flattenJSONObject(object)
        }

        var args: [String: String] = [:]
        let parts = trimmed.split(separator: " ")
        for part in parts {
            let item = String(part)
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            if pair.count == 2 {
                args[String(pair[0])] = String(pair[1])
            }
        }
        if args.isEmpty {
            args["query"] = trimmed
            args["content"] = trimmed
            args["title"] = String(trimmed.prefix(20))
            args["raw_text"] = trimmed
        }
        return args
    }

    /// 按工具名分发到具体 `run*` 实现。
    func execute(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> ToolExecutionResult {
        if invocation.name == "tool_list" {
            return ToolExecutionResult(
                toolName: "tool_list",
                outputText: "已接入工具（\(SparkToolName.all.count)）：\n\(SparkToolName.all.joined(separator: "\n"))",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        guard let tool = SparkToolName(rawValue: invocation.name) else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "未识别工具：\(invocation.name)",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        switch tool {
        case .fetchStepDetails:
            return await runFetchSteps(invocation: invocation, context: context)
        case .fetchSleepDetails:
            return await runFetchSleep(invocation: invocation, context: context)
        case .fetchEnergyDetails:
            return await runFetchEnergy(invocation: invocation, context: context)
        case .fetchNutritionDetails:
            return await runFetchNutrition(invocation: invocation, context: context)
        case .fetchWorkoutDetails:
            return await runFetchWorkout(invocation: invocation, context: context)
        case .makeNutritionData:
            return runMakeNutritionData(invocation: invocation, context: context)
        case .searchKnowledgeBag:
            return await runSearchKnowledgeBag(invocation: invocation, context: context)
        case .createKnowledgeDocument:
            return await runCreateKnowledgeDocument(invocation: invocation, context: context)
        case .saveMemory:
            return await runSaveMemory(invocation: invocation)
        case .retrieveMemory:
            return await runRetrieveMemory(invocation: invocation)
        case .updateMemory:
            return await runUpdateMemory(invocation: invocation)
        case .getCurrentMember:
            return await runGetCurrentMember(context: context)
        case .requestMemberSelection:
            return await runRequestMemberSelection(invocation: invocation, context: context)
        case .switchMember, .findMember:
            return await runFindMember(invocation: invocation)
        case .queryMemberProfile:
            return await runQueryMemberProfile(invocation: invocation, context: context)
        case .generateStructuredHealthCard:
            return await runGenerateStructuredHealthCard(invocation: invocation, context: context)
        case .listMemberHealthSources:
            return await runListMemberHealthSources(invocation: invocation, context: context)
        case .getHealthResourceReference:
            return await runGetHealthResourceReference(invocation: invocation, context: context)
        case .getHealthResourceContext:
            return await runGetHealthResourceContext(invocation: invocation, context: context)
        case .queryTasksByMember:
            return await runQueryTasksByMember(invocation: invocation, context: context)
        case .generateTask:
            return await runGenerateTask(invocation: invocation, context: context)
        case .generateChatTitle:
            return runGenerateChatTitle(invocation: invocation)
        case .createCanvas:
            return runCreateCanvas(invocation: invocation)
        case .editCanvas:
            return runEditCanvas(invocation: invocation)
        case .showCustomMessageCard:
            return await runShowCustomMessageCard(invocation: invocation, context: context)
        case .showMedicalRiskNotice:
            return runShowMedicalRiskNotice(invocation: invocation, context: context)
        case .askUserQuestion:
            return await runAskUserQuestion(invocation: invocation, context: context)
        case .insertHealthCitationSources:
            return runInsertHealthCitationSources(invocation: invocation, context: context)
        case .searchOnline,
             .readWebPage,
             .searchArxivPapers,
             .extractRemoteFileContent,
             .queryLocation,
             .getCurrentLocation,
             .searchNearbyLocations,
             .getRoute,
             .queryWeather,
             .searchCalendarAndReminders,
             .writeSystemEvent:
            return await runExternalConnectorTool(invocation: invocation, context: context)
        }
    }

    /// 数据源未接时的统一占位返回。
    func placeholder(tool: String, text: String) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: tool,
            outputText: "[\(tool)] \(text)",
            sensitive: false,
            shouldBypassModel: true
        )
    }
}
