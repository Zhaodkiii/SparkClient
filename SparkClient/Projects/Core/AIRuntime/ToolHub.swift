import Foundation

/// 聊天侧工具中枢：解析用户输入中的斜杠命令与 `SparkToolName`，执行后写审计；部分为占位或与配置中的外部 endpoint 路由说明。
final class ToolHub: @unchecked Sendable {
    private let auditStore: ToolAuditStore
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let aiSettingsRepository: any AISettingsRepository
    /// 知识库检索/创建：经用例访问 `CoreDataKnowledgeRepository`，避免在此直接操作持久化。
    private let searchKnowledgeUseCase: SearchKnowledgeUseCase
    private let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    private let logger: Logger

    /// 内存画布：标题 → 正文（`createCanvas` / `editCanvas` 使用，进程内有效）。
    private var canvasStore: [String: String] = [:]

    init(
        auditStore: ToolAuditStore,
        medicalQueryAPI: SparkMedicalQueryAPI,
        aiSettingsRepository: any AISettingsRepository,
        searchKnowledgeUseCase: SearchKnowledgeUseCase,
        createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase,
        logger: Logger = ConsoleLogger()
    ) {
        self.auditStore = auditStore
        self.medicalQueryAPI = medicalQueryAPI
        self.aiSettingsRepository = aiSettingsRepository
        self.searchKnowledgeUseCase = searchKnowledgeUseCase
        self.createKnowledgeDocumentUseCase = createKnowledgeDocumentUseCase
        self.logger = logger
    }

    /// 显式调试命令路由：`/audit_tools` 与 `/tool ...`。
    func runIfNeeded(userInput: String, memberID: Int?) async -> ToolHubResult {
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

        let context = ToolExecutionContext(memberID: memberID, locale: .current)
        let result = await execute(invocation: invocation, context: context)
        await appendAudit(invocation: invocation, context: context, result: result)
        return .executed(result)
    }

    /// 向模型暴露可调用工具定义（OpenAI tools schema 简化版）。
    func toolDefinitions() -> [AIRuntimeToolDefinition] {
        SparkToolName.all.map { toolName in
            AIRuntimeToolDefinition(
                name: toolName,
                summary: toolSummary(for: toolName),
                properties: toolProperties(for: toolName),
                required: toolRequiredFields(for: toolName)
            )
        }
    }

    /// 执行模型返回的 tool_call，并写入统一审计。
    func executeToolCall(name: String, arguments: String, memberID: Int?) async -> ToolExecutionResult {
        let invocation = ToolInvocation(name: name, arguments: parseArguments(arguments))
        let context = ToolExecutionContext(memberID: memberID, locale: .current)
        let result = await execute(invocation: invocation, context: context)
        await appendAudit(invocation: invocation, context: context, result: result)
        return result
    }

    /// `/audit_tools`：打印最近审计事件摘要。
    private func handleAuditTools() async -> ToolHubResult {
        let events = await auditStore.recent(limit: 20)
        if events.isEmpty {
            return .executed(
                ToolExecutionResult(
                    toolName: "audit_tools",
                    outputText: "最近没有工具调用审计记录。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            )
        }

        let lines = events.map { event in
            "[\(event.createdAt.formatted(date: .abbreviated, time: .shortened))] \(event.toolName) - \(event.status.rawValue)"
        }
        return .executed(
            ToolExecutionResult(
                toolName: "audit_tools",
                outputText: lines.joined(separator: "\n"),
                sensitive: false,
                shouldBypassModel: true
            )
        )
    }

    /// 将用户输入解析为显式调试命令：`/tool list` 与 `/tool <name> <args>`。
    private func parseToolInvocation(from input: String) -> ToolInvocation? {
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

    /// 与 HealthClient `ZDKOpenChatTools` 一致：工具文案键为 `ToolPrompts.strings` 中的 `tool.*`。
    private func toolFormat(_ key: String, _ args: CVarArg...) -> String {
        let template = AIPromptL10n(locale: .current).tool(key)
        return String(format: template, locale: Locale.current, arguments: Array(args))
    }

    private func td(_ key: String) -> String {
        AIPromptL10n(locale: .current).tool(key)
    }

    private func coordPropertySchema() -> AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: "object",
            description: td("tool.coord.wgs84_description"),
            objectProperties: [
                "latitude": AIRuntimeToolProperty(type: "number", description: td("tool.coord.latitude_sentence")),
                "longitude": AIRuntimeToolProperty(type: "number", description: td("tool.coord.longitude_sentence"))
            ],
            objectRequired: ["latitude", "longitude"]
        )
    }

    private func dateRangeProperties() -> [String: AIRuntimeToolProperty] {
        [
            "start_date": AIRuntimeToolProperty(type: "string", description: td("tool.date.start_yyyy_mm_dd"), format: "date"),
            "end_date": AIRuntimeToolProperty(type: "string", description: td("tool.date.end_yyyy_mm_dd"), format: "date")
        ]
    }

    private func toolSummary(for toolName: String) -> String {
        switch toolName {
        case SparkToolName.fetchStepDetails:
            return td("tool.summary.fetch_step_details")
        case SparkToolName.fetchEnergyDetails:
            return td("tool.summary.fetch_energy_details")
        case SparkToolName.fetchNutritionDetails:
            return td("tool.summary.fetch_nutrition_details")
        case SparkToolName.makeNutritionData:
            return td("tool.summary.make_nutrition_data")
        case SparkToolName.fetchSleepDetails:
            return td("tool.summary.fetch_sleep_details")
        case SparkToolName.fetchWorkoutDetails:
            return td("tool.summary.fetch_workout_details")
        case SparkToolName.generateStructuredHealthCard:
            return td("tool.summary.generate_structured_health_card")
        case SparkToolName.searchKnowledgeBag:
            return td("tool.summary.search_knowledge_bag")
        case SparkToolName.createKnowledgeDocument:
            return td("tool.summary.create_knowledge_document")
        case SparkToolName.searchCalendarAndReminders:
            return td("tool.summary.search_calendar_and_reminders")
        case SparkToolName.writeSystemEvent:
            return td("tool.summary.write_system_event")
        case SparkToolName.queryLocation:
            return td("tool.summary.query_location")
        case SparkToolName.getCurrentLocation:
            return td("tool.summary.get_current_location")
        case SparkToolName.searchNearbyLocations:
            return td("tool.summary.search_nearby_locations")
        case SparkToolName.getRoute:
            return td("tool.summary.get_route")
        case SparkToolName.queryWeather:
            return td("tool.summary.query_weather")
        case SparkToolName.saveMemory:
            return td("tool.summary.save_memory")
        case SparkToolName.retrieveMemory:
            return td("tool.summary.retrieve_memory")
        case SparkToolName.updateMemory:
            return td("tool.summary.update_memory")
        case SparkToolName.generateChatTitle:
            return td("tool.summary.generate_chat_title")
        case SparkToolName.showCustomMessageCard:
            return td("tool.summary.show_custom_message_card")
        case SparkToolName.getCurrentMember:
            return td("tool.summary.get_current_member")
        case SparkToolName.switchMember:
            return td("tool.summary.switch_member")
        case SparkToolName.findMember:
            return td("tool.summary.find_member")
        case SparkToolName.queryMemberProfile:
            return td("tool.summary.query_member_profile")
        case SparkToolName.searchOnline:
            return td("tool.summary.search_online")
        case SparkToolName.readWebPage:
            return td("tool.summary.read_web_page")
        case SparkToolName.searchArxivPapers:
            return td("tool.summary.search_arxiv_papers")
        case SparkToolName.extractRemoteFileContent:
            return td("tool.summary.extract_remote_file_content")
        case SparkToolName.createCanvas:
            return td("tool.summary.create_canvas")
        case SparkToolName.editCanvas:
            return td("tool.summary.edit_canvas")
        default:
            return toolFormat("tool.summary.generic", toolName)
        }
    }

    private func toolProperties(for toolName: String) -> [String: AIRuntimeToolProperty] {
        let coord = coordPropertySchema()
        switch toolName {
        case SparkToolName.fetchStepDetails,
             SparkToolName.fetchEnergyDetails,
             SparkToolName.fetchNutritionDetails,
             SparkToolName.fetchSleepDetails:
            return dateRangeProperties()
        case SparkToolName.makeNutritionData:
            return [
                "protein": AIRuntimeToolProperty(type: "number", description: td("tool.param.protein_g")),
                "carbohydrates": AIRuntimeToolProperty(type: "number", description: td("tool.param.carbohydrates_g")),
                "fat": AIRuntimeToolProperty(type: "number", description: td("tool.param.fat_g")),
                "energy": AIRuntimeToolProperty(type: "number", description: td("tool.param.energy_kcal"))
            ]
        case SparkToolName.fetchWorkoutDetails:
            return [
                "start_date": AIRuntimeToolProperty(type: "string", description: td("tool.date.start_yyyy_mm_dd"), format: "date"),
                "end_date": AIRuntimeToolProperty(type: "string", description: td("tool.date.end_yyyy_mm_dd"), format: "date"),
                "types": AIRuntimeToolProperty(
                    type: "array",
                    description: td("tool.param.activity_types_filter"),
                    arrayItems: AIRuntimeToolProperty(type: "string", description: td("tool.param.activity_type_item"))
                ),
                "max_items": AIRuntimeToolProperty(type: "integer", description: td("tool.param.max_items"))
            ]
        case SparkToolName.generateStructuredHealthCard:
            return [
                "category": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.report_type_enum"),
                    enumValues: ["medication", "prescription", "exam_report", "medical_case"]
                ),
                "raw_text": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.raw_text_distilled")
                ),
                "oss_file_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.oss_file_id_optional"))
            ]
        case SparkToolName.searchKnowledgeBag:
            return [
                "query": AIRuntimeToolProperty(type: "string", description: td("tool.param.query_keyword"))
            ]
        case SparkToolName.createKnowledgeDocument:
            return [
                "title": AIRuntimeToolProperty(type: "string", description: td("tool.param.doc_title")),
                "content": AIRuntimeToolProperty(type: "string", description: td("tool.param.doc_content_markdown"))
            ]
        case SparkToolName.searchCalendarAndReminders:
            return [
                "keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.keyword_title_notes")),
                "start_date": AIRuntimeToolProperty(type: "string", description: td("tool.param.start_date_inclusive"), format: "date"),
                "end_date": AIRuntimeToolProperty(type: "string", description: td("tool.param.end_date_inclusive"), format: "date"),
                "location": AIRuntimeToolProperty(type: "string", description: td("tool.param.location_keyword")),
                "event_type": AIRuntimeToolProperty(type: "string", description: td("tool.param.calendar_or_reminder_enum"), enumValues: ["calendar", "reminder"])
            ]
        case SparkToolName.writeSystemEvent:
            return [
                "type": AIRuntimeToolProperty(type: "string", description: td("tool.param.calendar_or_reminder_enum")),
                "title": AIRuntimeToolProperty(type: "string", description: td("tool.param.title")),
                "start_date": AIRuntimeToolProperty(type: "string", description: td("tool.param.start_iso8601_tz"), format: "date-time"),
                "end_date": AIRuntimeToolProperty(type: "string", description: td("tool.param.end_iso8601_tz"), format: "date-time"),
                "due_date": AIRuntimeToolProperty(type: "string", description: td("tool.param.due_iso8601_tz"), format: "date-time"),
                "location": AIRuntimeToolProperty(type: "string", description: td("tool.param.location_calendar_only")),
                "notes": AIRuntimeToolProperty(type: "string", description: td("tool.param.notes")),
                "priority": AIRuntimeToolProperty(type: "integer", description: td("tool.param.reminder_priority")),
                "reminder_minutes": AIRuntimeToolProperty(type: "integer", description: td("tool.param.reminder_minutes"))
            ]
        case SparkToolName.queryLocation:
            return [
                "keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.place_keyword"))
            ]
        case SparkToolName.getCurrentLocation:
            return [
                "query": AIRuntimeToolProperty(type: "string", description: td("tool.param.query_fixed_local"), enumValues: ["local"])
            ]
        case SparkToolName.searchNearbyLocations:
            return [
                "coordinate": coord,
                "keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.search_keyword_poi"))
            ]
        case SparkToolName.getRoute:
            let point = AIRuntimeToolProperty(
                type: "object",
                description: td("tool.param.latlon_point_object"),
                objectProperties: [
                    "latitude": AIRuntimeToolProperty(type: "number", description: td("tool.param.latitude")),
                    "longitude": AIRuntimeToolProperty(type: "number", description: td("tool.param.longitude"))
                ],
                objectRequired: ["latitude", "longitude"]
            )
            return [
                "start": point,
                "end": point,
                "mode": AIRuntimeToolProperty(type: "string", description: td("tool.param.transport_mode"), enumValues: ["driving", "walking", "transit"])
            ]
        case SparkToolName.queryWeather:
            return [
                "latitude": AIRuntimeToolProperty(type: "number", description: td("tool.param.latitude")),
                "longitude": AIRuntimeToolProperty(type: "number", description: td("tool.param.longitude")),
                "timeRange": AIRuntimeToolProperty(type: "string", description: td("tool.param.weather_time_range"))
            ]
        case SparkToolName.saveMemory:
            return [
                "content": AIRuntimeToolProperty(type: "string", description: td("tool.param.memory_content"))
            ]
        case SparkToolName.retrieveMemory:
            return [
                "keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.memory_keywords"))
            ]
        case SparkToolName.updateMemory:
            return [
                "originalContent": AIRuntimeToolProperty(type: "string", description: td("tool.param.memory_original")),
                "updatedContent": AIRuntimeToolProperty(type: "string", description: td("tool.param.memory_updated"))
            ]
        case SparkToolName.generateChatTitle:
            return [:]
        case SparkToolName.showCustomMessageCard:
            return [
                "card_type": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.attachment_types"),
                    enumValues: ["report_photo", "medicine_box_photo", "skin_photo"]
                )
            ]
        case SparkToolName.getCurrentMember, SparkToolName.switchMember:
            return [:]
        case SparkToolName.findMember:
            return [
                "name": AIRuntimeToolProperty(type: "string", description: td("tool.param.member_name_optional")),
                "relationship": AIRuntimeToolProperty(type: "string", description: td("tool.param.member_relationship_optional"))
            ]
        case SparkToolName.queryMemberProfile:
            return [
                "query_type": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.query_type_enum"),
                    enumValues: ["summary", "medications", "hospital_exams", "medical_records", "health_exams"]
                ),
                "member_id": AIRuntimeToolProperty(type: "string", description: td("tool.param.member_id_optional")),
                "days": AIRuntimeToolProperty(type: "integer", description: td("tool.param.days_optional")),
                "limit": AIRuntimeToolProperty(type: "integer", description: td("tool.param.limit_optional"))
            ]
        case SparkToolName.searchOnline, SparkToolName.searchArxivPapers:
            return [
                "query": AIRuntimeToolProperty(type: "string", description: td("tool.param.search_query"))
            ]
        case SparkToolName.readWebPage, SparkToolName.extractRemoteFileContent:
            return [
                "url": AIRuntimeToolProperty(type: "string", description: td("tool.param.url_full"))
            ]
        case SparkToolName.createCanvas:
            return [
                "title": AIRuntimeToolProperty(type: "string", description: td("tool.param.canvas_title")),
                "content": AIRuntimeToolProperty(type: "string", description: td("tool.param.canvas_body")),
                "type": AIRuntimeToolProperty(type: "string", description: td("tool.param.canvas_type_enum"), enumValues: ["text", "python", "html"])
            ]
        case SparkToolName.editCanvas:
            return [
                "title": AIRuntimeToolProperty(type: "string", description: td("tool.param.canvas_title_edit")),
                "patterns": AIRuntimeToolProperty(
                    type: "array",
                    description: td("tool.param.patterns_array"),
                    arrayItems: AIRuntimeToolProperty(type: "string", description: td("tool.param.regex_item"))
                ),
                "replacements": AIRuntimeToolProperty(
                    type: "array",
                    description: td("tool.param.replacements_array"),
                    arrayItems: AIRuntimeToolProperty(type: "string", description: td("tool.param.replacement_item"))
                )
            ]
        default:
            return [
                "query": AIRuntimeToolProperty(type: "string", description: td("tool.param.tool_query_generic"))
            ]
        }
    }

    private func toolRequiredFields(for toolName: String) -> [String] {
        switch toolName {
        case SparkToolName.fetchStepDetails,
             SparkToolName.fetchEnergyDetails,
             SparkToolName.fetchNutritionDetails,
             SparkToolName.fetchSleepDetails,
             SparkToolName.fetchWorkoutDetails:
            return ["start_date", "end_date"]
        case SparkToolName.makeNutritionData:
            return ["protein", "carbohydrates", "fat", "energy"]
        case SparkToolName.generateStructuredHealthCard:
            return ["category", "raw_text"]
        case SparkToolName.searchKnowledgeBag:
            return ["query"]
        case SparkToolName.createKnowledgeDocument:
            return ["title", "content"]
        case SparkToolName.queryLocation:
            return ["keyword"]
        case SparkToolName.getCurrentLocation:
            return ["query"]
        case SparkToolName.searchNearbyLocations:
            return ["coordinate", "keyword"]
        case SparkToolName.getRoute:
            return ["start", "end", "mode"]
        case SparkToolName.queryWeather:
            return ["latitude", "longitude", "timeRange"]
        case SparkToolName.saveMemory:
            return ["content"]
        case SparkToolName.retrieveMemory:
            return ["keyword"]
        case SparkToolName.updateMemory:
            return ["originalContent", "updatedContent"]
        case SparkToolName.showCustomMessageCard:
            return ["card_type"]
        case SparkToolName.queryMemberProfile:
            return ["query_type"]
        case SparkToolName.searchOnline, SparkToolName.searchArxivPapers:
            return ["query"]
        case SparkToolName.readWebPage, SparkToolName.extractRemoteFileContent:
            return ["url"]
        case SparkToolName.createCanvas:
            return ["title", "content", "type"]
        case SparkToolName.editCanvas:
            return ["patterns", "replacements"]
        case SparkToolName.searchCalendarAndReminders,
             SparkToolName.writeSystemEvent:
            return []
        default:
            return []
        }
    }

    /// 将模型返回的 JSON 参数展平：`{"coordinate":{"latitude":1,"longitude":2}}` → `coordinate.latitude` / `coordinate.longitude`；数组序列化为 JSON 字符串。
    private func flattenJSONObject(_ object: [String: Any]) -> [String: String] {
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
    private func parseArguments(_ raw: String) -> [String: String] {
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

    /// 按工具名分发到具体 `run*` 实现；多数结果 `shouldBypassModel: true` 由聊天层直接展示。
    private func execute(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        switch invocation.name {
        case "tool_list":
            return ToolExecutionResult(
                toolName: "tool_list",
                outputText: "已接入工具（\(SparkToolName.all.count)）：\n\(SparkToolName.all.joined(separator: "\n"))",
                sensitive: false,
                shouldBypassModel: true
            )

        case SparkToolName.fetchStepDetails:
            return await runFetchSteps(context: context)
        case SparkToolName.fetchSleepDetails:
            return await runFetchSleep(context: context)
        case SparkToolName.fetchEnergyDetails,
             SparkToolName.fetchNutritionDetails,
             SparkToolName.fetchWorkoutDetails,
             SparkToolName.makeNutritionData:
            return placeholder(
                tool: invocation.name,
                text: "当前仓库尚无该类原始数据源，工具入口已接通。"
            )

        case SparkToolName.searchKnowledgeBag:
            return await runSearchKnowledgeBag(invocation: invocation)
        case SparkToolName.createKnowledgeDocument:
            return await runCreateKnowledgeDocument(invocation: invocation)

        case SparkToolName.saveMemory:
            return await runSaveMemory(invocation: invocation)
        case SparkToolName.retrieveMemory:
            return await runRetrieveMemory(invocation: invocation)
        case SparkToolName.updateMemory:
            return await runUpdateMemory(invocation: invocation)

        case SparkToolName.getCurrentMember:
            return await runGetCurrentMember(context: context)
        case SparkToolName.switchMember, SparkToolName.findMember:
            return await runFindMember(invocation: invocation)
        case SparkToolName.queryMemberProfile:
            return await runQueryMemberProfile(invocation: invocation, context: context)

        case SparkToolName.generateStructuredHealthCard:
            return await runGenerateStructuredHealthCard(invocation: invocation, context: context)
        case SparkToolName.generateChatTitle:
            return runGenerateChatTitle(invocation: invocation)
        case SparkToolName.createCanvas:
            return runCreateCanvas(invocation: invocation)
        case SparkToolName.editCanvas:
            return runEditCanvas(invocation: invocation)

        case SparkToolName.showCustomMessageCard:
            let cardType = (invocation.arguments["card_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = cardType.isEmpty ? "" : "（\(cardType)）"
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "已展示上传/拍照卡片入口\(hint)，请继续引导用户上传材料。",
                sensitive: false,
                shouldBypassModel: true
            )

        case SparkToolName.searchOnline,
             SparkToolName.readWebPage,
             SparkToolName.searchArxivPapers,
             SparkToolName.extractRemoteFileContent,
             SparkToolName.queryLocation,
             SparkToolName.getCurrentLocation,
             SparkToolName.searchNearbyLocations,
             SparkToolName.getRoute,
             SparkToolName.queryWeather,
             SparkToolName.searchCalendarAndReminders,
             SparkToolName.writeSystemEvent:
            return await runExternalConnectorTool(invocation: invocation)

        default:
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "未识别工具：\(invocation.name)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 从健康指标仓库汇总最近步数记录。
    private func runFetchSteps(context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let memberID = context.memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchStepDetails,
                outputText: "未选择成员，无法查询步数。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        return ToolExecutionResult(
            toolName: SparkToolName.fetchStepDetails,
            outputText: "成员ID=\(memberID)；当前版本步数数据按档案维度存储，成员维度查询暂未启用。",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 从健康指标仓库汇总最近睡眠时长记录。
    private func runFetchSleep(context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let memberID = context.memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: "未选择成员，无法查询睡眠。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        return ToolExecutionResult(
            toolName: SparkToolName.fetchSleepDetails,
            outputText: "成员ID=\(memberID)；当前版本睡眠数据按档案维度存储，成员维度查询暂未启用。",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 在本地知识库中按标题、正文和切块检索知识片段。
    private func runSearchKnowledgeBag(invocation: ToolInvocation) async -> ToolExecutionResult {
        let query = invocation.arguments["query"] ?? invocation.arguments["content"] ?? ""
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.searchKnowledgeBag,
                outputText: "知识库检索失败：query 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let results = try await searchKnowledgeUseCase.execute(query: trimmed, limit: 5)
            guard results.isEmpty == false else {
                return ToolExecutionResult(
                    toolName: SparkToolName.searchKnowledgeBag,
                    outputText: "知识库未匹配到相关文档。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }

            let lines = results.enumerated().map { index, result in
                let prefix = "[\(index + 1)] \(result.title)"
                return "\(prefix)\n\(result.excerpt)"
            }
            return ToolExecutionResult(
                toolName: SparkToolName.searchKnowledgeBag,
                outputText: lines.joined(separator: "\n\n"),
                sensitive: false,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.searchKnowledgeBag,
                outputText: "知识库搜索失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 创建并持久化本地知识文档。
    private func runCreateKnowledgeDocument(invocation: ToolInvocation) async -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "未命名文档").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (invocation.arguments["content"] ?? invocation.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: "知识文档创建失败：content 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let document = try await createKnowledgeDocumentUseCase.execute(
                KnowledgeDocumentDraft(
                    title: title.isEmpty ? "未命名文档" : title,
                    content: content,
                    source: .tool
                )
            )
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: "知识文档已创建：\(document.title)",
                sensitive: false,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: "知识文档保存失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 将内容追加到 `memoryArchive` 并保存。
    private func runSaveMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let content = (invocation.arguments["content"] ?? invocation.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆保存失败：content 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        var snapshot = await aiSettingsRepository.loadSnapshot()
        let title = String(content.prefix(20))
        snapshot.memoryArchive.append(
            MemoryArchive(title: title.isEmpty ? "新记忆" : title, content: content, pinned: false, timestamp: Date())
        )

        do {
            try await aiSettingsRepository.save(snapshot: snapshot)
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆已保存：\(title)",
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆保存失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 无 query 时取最近几条记忆；有 query 时在 `memoryArchive` 中筛选。
    private func runRetrieveMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["keyword"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let hits: [MemoryArchive]
        if query.isEmpty {
            hits = Array(snapshot.memoryArchive.suffix(5))
        } else {
            hits = snapshot.memoryArchive.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query)
            }
        }

        if hits.isEmpty {
            return ToolExecutionResult(
                toolName: SparkToolName.retrieveMemory,
                outputText: "未检索到相关记忆。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let lines = hits.suffix(5).map { "- \($0.title)：\(String($0.content.prefix(100)))" }
        return ToolExecutionResult(
            toolName: SparkToolName.retrieveMemory,
            outputText: lines.joined(separator: "\n"),
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 按原文或标题匹配一条记忆并替换正文、更新时间。
    private func runUpdateMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let original = (invocation.arguments["originalContent"] ?? invocation.arguments["original"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = (invocation.arguments["updatedContent"] ?? invocation.arguments["updated"] ?? invocation.arguments["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard original.isEmpty == false, updated.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆更新失败：需要 originalContent 与 updatedContent。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        var snapshot = await aiSettingsRepository.loadSnapshot()
        guard let index = snapshot.memoryArchive.firstIndex(where: { $0.content == original || $0.title == original }) else {
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆更新失败：未找到原始内容。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        snapshot.memoryArchive[index].content = updated
        snapshot.memoryArchive[index].timestamp = Date()

        do {
            try await aiSettingsRepository.save(snapshot: snapshot)
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆已更新：\(snapshot.memoryArchive[index].title)",
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆更新失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 根据上下文 `memberID` 在医疗数据中解析当前成员简介。
    private func runGetCurrentMember(context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let memberID = context.memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.getCurrentMember,
                outputText: "当前未选择成员。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let data: SparkMedicalSyncAPI.RemoteMemberCompleteData
        do {
            data = try await medicalQueryAPI.fetchMemberCompleteData(memberID: memberID)
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.getCurrentMember,
                outputText: "当前成员数据加载失败。",
                sensitive: false,
                shouldBypassModel: true
            )
        }
        let member = data.member
        let output = "当前成员：\(member.name)，关系：\(member.relationship)。"
        return ToolExecutionResult(
            toolName: SparkToolName.getCurrentMember,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 按名称与/或关系模糊筛选成员（与 HealthClient `find_member` 参数对齐）。
    private func runFindMember(invocation: ToolInvocation) async -> ToolExecutionResult {
        let nameQuery = (invocation.arguments["query"] ?? invocation.arguments["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let relationshipQuery = (invocation.arguments["relationship"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remotes = (try? await medicalQueryAPI.listMembers()) ?? []
        let members: [Member] = remotes.map(\.domainModel)
        let filtered: [Member]
        if nameQuery.isEmpty && relationshipQuery.isEmpty {
            filtered = members
        } else {
            filtered = members.filter { member in
                let nameHit = nameQuery.isEmpty ? false : member.name.localizedCaseInsensitiveContains(nameQuery)
                let relHit = relationshipQuery.isEmpty ? false : member.relationship.localizedCaseInsensitiveContains(relationshipQuery)
                if nameQuery.isEmpty == false && relationshipQuery.isEmpty == false {
                    return nameHit || relHit
                }
                if nameQuery.isEmpty == false {
                    return nameHit
                }
                return relHit
            }
        }

        if filtered.isEmpty {
            return ToolExecutionResult(
                toolName: SparkToolName.findMember,
                outputText: "未找到匹配成员。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let lines = filtered.prefix(8).map { "- \($0.name)（关系：\($0.relationship)）" }
        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: lines.joined(separator: "\n"),
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 汇总指定或当前成员的病例/报告/处方等数量统计（`query_type` / `member_id`；兼容旧参数名 `patient_id`。Spark 用整型字符串）。
    private func runQueryMemberProfile(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let queryType = (invocation.arguments["query_type"] ?? "summary").trimmingCharacters(in: .whitespacesAndNewlines)
        let targetMemberID: Int? = {
            if let value = invocation.arguments["member_id"], let id = Int(value) {
                return id
            }
            if let value = invocation.arguments["patient_id"], let id = Int(value) {
                return id
            }
            return context.memberID
        }()

        guard let memberID = targetMemberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.queryMemberProfile,
                outputText: "未找到成员档案。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let data: SparkMedicalSyncAPI.RemoteMemberCompleteData
        do {
            data = try await medicalQueryAPI.fetchMemberCompleteData(memberID: memberID)
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.queryMemberProfile,
                outputText: "成员医疗数据加载失败。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let member = data.member
        let cases = data.medicalCases ?? []
        let caseCount = cases.count
        let symptomCount = (data.symptoms ?? []).count
        let visitCount = (data.visits ?? []).count
        let surgeryCount = (data.surgeries ?? []).count
        let followUpCount = (data.followUps ?? []).count
        let healthExamCount = (data.healthExamReports ?? []).count
        let examCount = (data.examinationReports ?? []).count
        let examDetailCount = 0
        let reportCount = 0
        let batches = data.prescriptionBatches ?? []
        let medicationCount = batches.flatMap { $0.medications ?? [] }.count + (data.standaloneMedications ?? []).count
        let daysNote = invocation.arguments["days"] ?? "3"
        let limitNote = invocation.arguments["limit"] ?? "3"

        let output = """
        query_type: \(queryType)
        参数提示：days=\(daysNote)（用药窗口）, limit=\(limitNote)（病例条数上限，Spark 当前汇总为全量计数）
        成员：\(member.name)
        关系：\(member.relationship)
        病例数：\(caseCount)
        症状数：\(symptomCount)
        就诊数：\(visitCount)
        手术数：\(surgeryCount)
        随访数：\(followUpCount)
        检查报告数：\(examCount)
        体检主表数：\(healthExamCount)
        医技明细数：\(examDetailCount)
        医疗报告数：\(reportCount)
        用药数：\(medicationCount)
        """

        return ToolExecutionResult(
            toolName: SparkToolName.queryMemberProfile,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 占位：根据 `raw_text` 等参数生成结构化健康卡片描述（未接真实结构化管线）。
    private func runGenerateStructuredHealthCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let memberID = context.memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: "未选择成员，无法生成结构化健康卡片。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let category = (invocation.arguments["category"] ?? "medical_case").lowercased()
        let rawText = (invocation.arguments["raw_text"] ?? invocation.arguments["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawText.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: "生成失败：raw_text 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let title = "\(category)_\(Date().formatted(date: .abbreviated, time: .omitted))"
        let summary = String(rawText.prefix(120))
        let oss = invocation.arguments["oss_file_id"].map { ", oss_file_id=\($0)" } ?? ""
        let output = "已生成结构化卡片：category=\(category), title=\(title), member=\(memberID)\(oss), summary=\(summary)"

        return ToolExecutionResult(
            toolName: SparkToolName.generateStructuredHealthCard,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 从参数截取短标题（最多 18 字）作为会话标题建议。
    private func runGenerateChatTitle(invocation: ToolInvocation) -> ToolExecutionResult {
        let source = invocation.arguments["content"] ?? invocation.arguments["query"] ?? "新对话"
        let title = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(18))
        return ToolExecutionResult(
            toolName: SparkToolName.generateChatTitle,
            outputText: title.isEmpty ? "新对话" : title,
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 在内存 `canvasStore` 中新建画布条目（`type` 与 HealthClient 一致，仅存进程内正文）。
    private func runCreateCanvas(invocation: ToolInvocation) -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "默认画布").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = invocation.arguments["content"] ?? ""
        let canvasType = (invocation.arguments["type"] ?? "text").trimmingCharacters(in: .whitespacesAndNewlines)
        canvasStore[title] = content
        let kind = canvasType.isEmpty ? "text" : canvasType
        return ToolExecutionResult(
            toolName: SparkToolName.createCanvas,
            outputText: "画布已创建：\(title)，类型：\(kind)",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 用 `patterns`/`replacements` 正则替换更新画布，或与 Health 一致地整段 `content` 覆盖。
    private func runEditCanvas(invocation: ToolInvocation) -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "默认画布").trimmingCharacters(in: .whitespacesAndNewlines)
        guard canvasStore[title] != nil else {
            return ToolExecutionResult(
                toolName: SparkToolName.editCanvas,
                outputText: "画布不存在：\(title)",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        if let patternsRaw = invocation.arguments["patterns"],
           let replRaw = invocation.arguments["replacements"],
           let pData = patternsRaw.data(using: .utf8),
           let rData = replRaw.data(using: .utf8),
           let patterns = try? JSONSerialization.jsonObject(with: pData) as? [String],
           let replacements = try? JSONSerialization.jsonObject(with: rData) as? [String],
           patterns.count == replacements.count,
           patterns.isEmpty == false {
            var body = canvasStore[title] ?? ""
            for index in patterns.indices {
                guard let regex = try? NSRegularExpression(pattern: patterns[index], options: []) else { continue }
                let range = NSRange(body.startIndex..., in: body)
                body = regex.stringByReplacingMatches(in: body, options: [], range: range, withTemplate: replacements[index])
            }
            canvasStore[title] = body
            return ToolExecutionResult(
                toolName: SparkToolName.editCanvas,
                outputText: "画布已按正则更新：\(title)",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        if let content = invocation.arguments["content"] {
        canvasStore[title] = content
        return ToolExecutionResult(
            toolName: SparkToolName.editCanvas,
                outputText: "画布已整段更新：\(title)",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        return ToolExecutionResult(
            toolName: SparkToolName.editCanvas,
            outputText: "请提供 patterns 与 replacements（与 ZDK 一致的 JSON 数组字符串），或提供 content 进行整段覆盖。",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 联网/地图/日历等外部工具：根据 `toolKeys` 解析 endpoint，当前仅返回路由占位说明。
    private func runExternalConnectorTool(invocation: ToolInvocation) async -> ToolExecutionResult {
        let snapshot = await aiSettingsRepository.loadSnapshot()
        let endpoint = resolveEndpoint(for: invocation.name, toolKeys: snapshot.toolKeys)
        let payloadSummary = invocation.arguments
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")

        let output = """
        工具 \(invocation.name) 已接入 SparkClient 路由。
        endpoint=\(endpoint ?? "未配置")
        args=\(payloadSummary.isEmpty ? "<empty>" : payloadSummary)
        当前为本地执行占位；如需真实联网调用，请在对应 toolClass 网关实现 HTTP 适配。
        """

        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: output,
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 将工具名映射到配置里的 `toolClass`（weather/map/calendar/code/tool），再取可用 `requestURL`。
    private func resolveEndpoint(for toolName: String, toolKeys: [ToolKeys]) -> String? {
        let toolClass: String
        switch toolName {
        case SparkToolName.queryWeather:
            toolClass = "weather"
        case SparkToolName.queryLocation,
             SparkToolName.getCurrentLocation,
             SparkToolName.searchNearbyLocations,
             SparkToolName.getRoute:
            toolClass = "map"
        case SparkToolName.searchCalendarAndReminders,
             SparkToolName.writeSystemEvent:
            toolClass = "calendar"
        case SparkToolName.searchArxivPapers:
            toolClass = "code"
        default:
            toolClass = "tool"
        }

        return toolKeys.first(where: { $0.toolClass == toolClass && $0.isUsing })?.requestURL
            ?? toolKeys.first(where: { $0.toolClass == toolClass })?.requestURL
    }

    /// 数据源未接时的统一占位返回。
    private func placeholder(tool: String, text: String) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: tool,
            outputText: "[\(tool)] \(text)",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 将本次工具调用写入审计存储，并按输出是否含「失败」粗判状态。
    private func appendAudit(
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        result: ToolExecutionResult
    ) async {
        let status: ToolAuditStatus = result.outputText.localizedCaseInsensitiveContains("失败") ? .failed : .success
        await auditStore.append(
            ToolAuditEvent(
                toolName: invocation.name,
                memberID: context.memberID,
                inputSummary: String(invocation.arguments.description.prefix(200)),
                outputSummary: String(result.outputText.prefix(200)),
                status: status
            )
        )
        logger.info(
            "工具执行完成，tool=\(invocation.name), status=\(status.rawValue), bypassModel=\(result.shouldBypassModel), sensitive=\(result.sensitive)",
            module: .aiConfig
        )
    }

    private func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }
}
