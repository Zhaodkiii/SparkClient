import Foundation

/// 聊天侧工具中枢：解析用户输入中的斜杠命令与 `SparkToolName`，执行后写审计；部分为占位或与配置中的外部 endpoint 路由说明。
final class ToolHub: @unchecked Sendable {
    private let auditStore: ToolAuditStore
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let aiSettingsRepository: any AISettingsRepository
    private let aiConfigCenter: AIConfigCenter
    private let runtimeService: any AIRuntimeServing
    private let taskService: TaskService
    /// 知识库检索/创建：经用例访问 `CoreDataKnowledgeRepository`，避免在此直接操作持久化。
    private let searchKnowledgeUseCase: SearchKnowledgeUseCase
    private let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    /// 与上传流水线共用：对话工具 `generate_structured_health_card` 的结构化抽取。
    private let typedMedicalDocumentExtractor: DefaultTypedMedicalDocumentExtractor
    /// 异步将卡片合并回当前助手消息（Core Data + `ChatStateStore`）。
    private let structuredHealthCardMergeCoordinator: StructuredHealthCardMergeCoordinator
    private let logger: Logger

    /// 内存画布：标题 → 正文（`createCanvas` / `editCanvas` 使用，进程内有效）。
    private var canvasStore: [String: String] = [:]

    init(
        auditStore: ToolAuditStore,
        medicalQueryAPI: SparkMedicalQueryAPI,
        aiSettingsRepository: any AISettingsRepository,
        aiConfigCenter: AIConfigCenter,
        runtimeService: any AIRuntimeServing,
        taskService: TaskService,
        searchKnowledgeUseCase: SearchKnowledgeUseCase,
        createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase,
        typedMedicalDocumentExtractor: DefaultTypedMedicalDocumentExtractor,
        structuredHealthCardMergeCoordinator: StructuredHealthCardMergeCoordinator,
        logger: Logger = ConsoleLogger()
    ) {
        self.auditStore = auditStore
        self.medicalQueryAPI = medicalQueryAPI
        self.aiSettingsRepository = aiSettingsRepository
        self.aiConfigCenter = aiConfigCenter
        self.runtimeService = runtimeService
        self.taskService = taskService
        self.searchKnowledgeUseCase = searchKnowledgeUseCase
        self.createKnowledgeDocumentUseCase = createKnowledgeDocumentUseCase
        self.typedMedicalDocumentExtractor = typedMedicalDocumentExtractor
        self.structuredHealthCardMergeCoordinator = structuredHealthCardMergeCoordinator
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
    func executeToolCall(
        name: String,
        arguments: String,
        memberID: Int?,
        threadID: UUID? = nil,
        assistantMessageClientID: UUID? = nil
    ) async -> ToolExecutionResult {
        let invocation = ToolInvocation(name: name, arguments: parseArguments(arguments))
        let context = ToolExecutionContext(
            memberID: memberID,
            locale: .current,
            assistantMessageClientID: assistantMessageClientID,
            threadID: threadID
        )
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
        case SparkToolName.queryTasksByMember:
            return td("tool.summary.query_tasks_by_member")
        case SparkToolName.generateTask:
            return td("tool.summary.generate_task")
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
                "report_type": AIRuntimeToolProperty(
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
        case SparkToolName.queryTasksByMember:
            return [
                "member_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.member_id_for_task")),
                "include_completed": AIRuntimeToolProperty(type: "boolean", description: td("tool.param.include_completed_optional")),
                "limit": AIRuntimeToolProperty(type: "integer", description: td("tool.param.max_items"))
            ]
        case SparkToolName.generateTask:
            return [
                "member_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.member_id_for_task")),
                "user_input": AIRuntimeToolProperty(type: "string", description: td("tool.param.user_input_for_extraction")),
                "require_query_first": AIRuntimeToolProperty(type: "boolean", description: td("tool.param.require_query_first"))
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
            return ["report_type", "raw_text"]
        case SparkToolName.queryTasksByMember:
            return []
        case SparkToolName.generateTask:
            return ["user_input"]
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
            return await runFetchSleep(invocation: invocation, context: context)
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
        case SparkToolName.queryTasksByMember:
            return await runQueryTasksByMember(invocation: invocation, context: context)
        case SparkToolName.generateTask:
            return await runGenerateTask(invocation: invocation, context: context)
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
    private func runFetchSleep(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        guard let memberID = context.memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: "未选择成员，无法查询睡眠。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let range = resolveSleepRange(arguments: invocation.arguments)
        let model = buildSleepModel(from: range.start, to: range.end)
        let json = (try? JSONEncoder().encode(model))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{}"
        let output = """
        sleep_model=\(json)
        \(model.toReadableText())
        """

        return ToolExecutionResult(
            toolName: SparkToolName.fetchSleepDetails,
            outputText: "member_id=\(memberID)\n\(output)",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    private func resolveSleepRange(arguments: [String: String]) -> (start: Date, end: Date) {
        let now = Date()
        let end = min(parseDate(arguments["end_date"]) ?? now, now)
        let start = parseDate(arguments["start_date"])
            ?? Calendar.current.date(byAdding: .day, value: -2, to: end)
            ?? end
        if start > end {
            return (end, end)
        }
        return (start, end)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = Calendar.current.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: value)
    }

    private func buildSleepModel(from startDate: Date, to endDate: Date) -> ChatHealthSleepModel {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: startDate)
        let dayEnd = calendar.startOfDay(for: endDate)
        let daysCount = max(1, (calendar.dateComponents([.day], from: dayStart, to: dayEnd).day ?? 0) + 1)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var days: [ChatHealthSleepModel.Day] = []
        for offset in 0..<min(daysCount, 7) {
            guard let baseDay = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            guard let sleepStart = calendar.date(bySettingHour: 23, minute: 10, second: 0, of: baseDay),
                  let sleepEnd = calendar.date(byAdding: .hour, value: 7, to: sleepStart)
            else { continue }

            let total = Int(sleepEnd.timeIntervalSince(sleepStart) / 60)
            let deep = Int(Double(total) * 0.22)
            let rem = Int(Double(total) * 0.19)
            let awake = 24
            let core = max(0, total - deep - rem - awake)

            let timeline = buildSleepTimeline(
                sleepStart: sleepStart,
                totalMinutes: total,
                deepMinutes: deep,
                coreMinutes: core,
                remMinutes: rem,
                awakeMinutes: awake
            )

            let summary = ChatHealthSleepModel.Summary(
                totalSleepMinutes: total,
                start: Int64(sleepStart.timeIntervalSince1970),
                end: Int64(sleepEnd.timeIntervalSince1970),
                startText: nil,
                endText: nil
            )
            let stages = ChatHealthSleepModel.StageBreakdown(
                deep: deep,
                core: core,
                rem: rem,
                awake: awake,
                unspecified: 0
            )
            days.append(
                ChatHealthSleepModel.Day(
                    date: formatter.string(from: baseDay),
                    summary: summary,
                    timeline: timeline,
                    stages: stages
                )
            )
        }

        return ChatHealthSleepModel(
            generatedAt: Int64(Date().timeIntervalSince1970),
            days: days
        )
    }

    private func buildSleepTimeline(
        sleepStart: Date,
        totalMinutes: Int,
        deepMinutes: Int,
        coreMinutes: Int,
        remMinutes: Int,
        awakeMinutes: Int
    ) -> [ChatHealthSleepModel.Segment] {
        let blocks: [(ChatHealthSleepModel.Stage, Int)] = [
            (.core, Int(Double(coreMinutes) * 0.45)),
            (.deep, Int(Double(deepMinutes) * 0.5)),
            (.core, Int(Double(coreMinutes) * 0.35)),
            (.rem, Int(Double(remMinutes) * 0.6)),
            (.awake, awakeMinutes),
            (.core, max(0, coreMinutes - Int(Double(coreMinutes) * 0.8))),
            (.deep, max(0, deepMinutes - Int(Double(deepMinutes) * 0.5))),
            (.rem, max(0, remMinutes - Int(Double(remMinutes) * 0.6)))
        ].filter { $0.1 > 0 }

        var cursor = Int64(sleepStart.timeIntervalSince1970)
        let totalSeconds = max(1, totalMinutes * 60)
        var segments: [ChatHealthSleepModel.Segment] = []
        for (stage, minute) in blocks {
            let duration = Int64(minute * 60)
            let start = cursor
            let end = cursor + duration
            let startPercent = Double(start - Int64(sleepStart.timeIntervalSince1970)) / Double(totalSeconds)
            let widthPercent = Double(duration) / Double(totalSeconds)
            segments.append(
                ChatHealthSleepModel.Segment(
                    stage: stage,
                    start: start,
                    end: end,
                    startPercent: max(0, startPercent),
                    widthPercent: max(0, widthPercent),
                    startText: nil,
                    endText: nil
                )
            )
            cursor = end
        }
        return segments
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

    /// 生成知识文档草稿（用于消息内知识卡预览），不在工具阶段直接落库。
    /// 真正保存由聊天气泡中的“保存到知识库”按钮触发，保持 AI_Hanlin 一致的确认式交互。
    private func runCreateKnowledgeDocument(invocation: ToolInvocation) async -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "未命名文档").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = (invocation.arguments["content"] ?? invocation.arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.createKnowledgeDocument,
                outputText: "知识文档草稿生成失败：content 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }
        logger.info(
            "create_knowledge_document 生成预览草稿，title=\(title.isEmpty ? "未命名文档" : title), contentLength=\(content.count)",
            module: .aiConfig
        )

        // 统一输出为 JSON，便于聊天发送链路稳定解析为 knowledge_card。
        let payload: [String: String] = [
            "status": "preview",
            "title": title.isEmpty ? "未命名文档" : title,
            "content": content
        ]
        let outputText: String
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            outputText = text
        } else {
            outputText = """
            status=preview
            title=\(title.isEmpty ? "未命名文档" : title)
            content=\(content)
            """
        }
        return ToolExecutionResult(
            toolName: SparkToolName.createKnowledgeDocument,
            outputText: outputText,
            sensitive: false,
            shouldBypassModel: true
        )
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

        var snapshot = await aiConfigCenter.currentSnapshot()
        let title = String(content.prefix(20))
        snapshot.memoryArchive.append(
            MemoryArchive(title: title.isEmpty ? "新记忆" : title, content: content, pinned: false, timestamp: Date())
        )

        do {
            try await aiSettingsRepository.save(snapshot: snapshot)
            await aiConfigCenter.rebuildRuntimeCache(from: snapshot)
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
        let snapshot = await aiConfigCenter.currentSnapshot()
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

        var snapshot = await aiConfigCenter.currentSnapshot()
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
            await aiConfigCenter.rebuildRuntimeCache(from: snapshot)
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

    /// 对齐 HealthClient：同步返回系统提示，结构化卡片在后台抽取完成后合并到当前助手消息。
    private func runGenerateStructuredHealthCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let l10n = AIPromptL10n(locale: context.locale)
        let hintTemplate = l10n.tool(
            "tool.async.structured_health_card.model_hint",
            fallback: """
            [System] Structured save cards are generating in the background. Continue interpreting from the user message without waiting; cards appear below this reply.
            """
        )
        guard let memberID = context.memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: l10n.tool(
                    "tool.error.structured_health_card.no_member",
                    fallback: "No member selected; cannot generate structured health cards."
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let reportType = (invocation.arguments["report_type"] ?? invocation.arguments["category"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let rawText = (invocation.arguments["raw_text"] ?? invocation.arguments["content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawText.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: l10n.tool(
                    "tool.error.structured_health_card.empty_raw_text",
                    fallback: "Missing raw_text (distilled excerpt)."
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }

        guard let threadID = context.threadID, let assistantID = context.assistantMessageClientID else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: l10n.tool(
                    "tool.error.structured_health_card.no_message_binding",
                    fallback: "[System] Internal error: assistant message not bound."
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let effectiveReportType = reportType.isEmpty ? "medical_case" : reportType
        let ossFileId = invocation.arguments["oss_file_id"].flatMap { Int($0) }
        let merge = structuredHealthCardMergeCoordinator
        let extractor = typedMedicalDocumentExtractor

        Task {
            do {
                let output = try await extractor.extractFromChatDistilledText(
                    memberID: memberID,
                    reportType: effectiveReportType,
                    rawText: rawText
                )
                let delta = ChatStructuredHealthCardsPayloadBuilder.appendPayloads(
                    from: output,
                    memberID: memberID,
                    ossFileId: ossFileId
                )
                await merge.mergeAppendWhenAssistantMessageReady(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    delta: delta
                )
            } catch {
                logger.warning(
                    "generate_structured_health_card 抽取失败：\(error.localizedDescription)",
                    module: .aiConfig
                )
                let delta = ChatStructuredHealthCardsPayloadBuilder.extractionFailureBlob(
                    memberID: memberID,
                    reportType: effectiveReportType,
                    ossFileId: ossFileId
                )
                await merge.mergeAppendWhenAssistantMessageReady(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    delta: delta
                )
            }
        }

        return ToolExecutionResult(
            toolName: SparkToolName.generateStructuredHealthCard,
            outputText: hintTemplate,
            sensitive: false,
            shouldBypassModel: false
        )
    }

    /// 任务查询工具：按成员维度返回主任务与子任务信息，供后续任务生成去重。
    private func runQueryTasksByMember(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let memberID = await resolveTargetMemberID(invocation: invocation, context: context)
        guard let memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.queryTasksByMember,
                outputText: #"{"ok":false,"error":"no_available_member"}"#,
                sensitive: false,
                shouldBypassModel: true
            )
        }
        let includeCompleted = parseBool(invocation.arguments["include_completed"], defaultValue: true)
        let limit = max(1, min(Int(invocation.arguments["limit"] ?? "") ?? 50, 200))

        do {
            var tasks = try await taskService.fetchTasks(memberID: memberID, since: nil)
            if includeCompleted == false {
                tasks.removeAll { $0.status != .pending }
            }
            tasks = Array(tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
            let payload = TaskQueryToolPayload(
                ok: true,
                memberID: memberID,
                queriedAt: iso8601(Date()),
                total: tasks.count,
                tasks: tasks
            )
            return ToolExecutionResult(
                toolName: SparkToolName.queryTasksByMember,
                outputText: encodeJSON(payload) ?? #"{"ok":false,"error":"encode_failed"}"#,
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.queryTasksByMember,
                outputText: #"{"ok":false,"error":"task_query_failed"}"#,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 任务生成工具：先查询任务，再执行抽取与相似度判断，最后只输出任务卡片 JSON（待用户确认）。
    private func runGenerateTask(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let memberID = await resolveTargetMemberID(invocation: invocation, context: context)
        guard let memberID else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateTask,
                outputText: #"{"ok":false,"error":"no_available_member"}"#,
                sensitive: false,
                shouldBypassModel: true
            )
        }
        let userInput = (
            invocation.arguments["user_input"]
            ?? invocation.arguments["query"]
            ?? invocation.arguments["content"]
            ?? invocation.arguments["raw_text"]
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard userInput.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateTask,
                outputText: #"{"ok":false,"error":"user_input_required"}"#,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        // 规则：生成前必须先查任务。这里在工具内部强制执行，确保流程不被模型跳过。
        let existingTasks: [HealthTask]
        do {
            existingTasks = try await taskService.fetchTasks(memberID: memberID, since: nil)
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.generateTask,
                outputText: #"{"ok":false,"error":"query_tasks_before_generate_failed"}"#,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let extracted = await extractTaskIntent(from: userInput)
        let similarTasks = findSimilarTasks(existing: existingTasks, extracted: extracted)
        if similarTasks.isEmpty == false {
            let response = TaskNoCreateToolPayload(
                ok: true,
                action: "no_create",
                reason: "similar_task_exists",
                queriedFirst: true,
                memberID: memberID,
                extracted: extracted,
                similarTasks: similarTasks.map {
                    TaskSimilarityItem(
                        taskID: $0.id,
                        title: $0.title,
                        type: $0.type.rawValue,
                        status: $0.status.rawValue,
                        updatedAt: iso8601($0.updatedAt)
                    )
                }
            )
            return ToolExecutionResult(
                toolName: SparkToolName.generateTask,
                outputText: encodeJSON(response) ?? #"{"ok":false,"error":"encode_failed"}"#,
                sensitive: true,
                shouldBypassModel: true
            )
        }

        let now = Date()
        let taskType = mapTaskType(extracted.taskType)
        let startAt = parseISODate(extracted.timeInfo.startTime) ?? now
        let repeatType = mapRepeatType(period: extracted.timeInfo.period, frequency: extracted.timeInfo.frequency)
        let dueAt = resolveDueDate(startAt: startAt, repeatType: repeatType)
        let priority: HealthTask.Priority = .medium

        let card = TaskToolCardPayload(
            id: -Int(now.timeIntervalSince1970),
            member: memberID,
            creator: nil,
            title: makeTaskTitle(extracted: extracted, type: taskType),
            description: makeTaskDescription(extracted: extracted, type: taskType),
            type: taskType.rawValue,
            startTime: iso8601(startAt),
            dueTime: dueAt.map(iso8601),
            repeatType: repeatType.rawValue,
            priority: priority.rawValue,
            businessType: "ai_task_generation",
            businessID: "",
            source: HealthTask.Source.ai.rawValue,
            status: TaskCard.CardStatus.pending.rawValue,
            extractPayload: extracted.asStringMap(),
            taskPayload: buildTaskPayloadStrings(memberID: memberID, type: taskType, extracted: extracted, startAt: startAt, dueAt: dueAt, repeatType: repeatType, priority: priority),
            similarityPayload: [
                "queried_first": "true",
                "similar_count": "0",
                "member_source": invocation.arguments["member_id"] == nil ? "current_member_default" : "explicit_member"
            ],
            ignoredReason: "",
            confirmedTask: nil,
            createdAt: iso8601(now),
            updatedAt: iso8601(now)
        )
        let wrapper = TaskCardToolWrapper(taskCards: [card])
        return ToolExecutionResult(
            toolName: SparkToolName.generateTask,
            outputText: encodeJSON(wrapper) ?? #"{"ok":false,"error":"encode_failed"}"#,
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 使用现有抽取链路（AIRuntime + JSON 规整器）进行任务结构化抽取，失败时回退规则抽取。
    private func extractTaskIntent(from input: String) async -> TaskIntentExtraction {
        let prompt = PromptLocalizer(locale: .current).taskExtractionPrompt(userInput: input)
        do {
            let stream = try await runtimeService.generateTextStream(
                request: AIRuntimeTextRequest(
                    scenario: .medicalStructuredExtraction,
                    messages: [AIRuntimeMessage(role: .user, content: prompt)],
                    reasoning: .disabled
                )
            )
            let raw = try await collectStreamText(from: stream)
            let normalizer = MedicalDocumentModelJSONNormalizer()
            let normalized = normalizer.normalizedModelJSONText(raw)
            if let data = normalized.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(TaskIntentExtraction.self, from: data) {
                return decoded.normalized()
            }
        } catch {
            logger.warning("任务抽取模型失败，降级到规则抽取", module: .aiConfig)
        }
        return TaskIntentExtraction.ruleBased(from: input)
    }

    private func collectStreamText(from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>) async throws -> String {
        var text = ""
        var completedText = ""
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                text.append(delta)
            case .completed(let response):
                completedText = response.text
            case .reasoningDelta, .toolCallDelta:
                continue
            }
        }
        return text.isEmpty ? completedText : text
    }

    private func findSimilarTasks(existing: [HealthTask], extracted: TaskIntentExtraction) -> [HealthTask] {
        let type = mapTaskType(extracted.taskType)
        let target = extracted.targetMetric.lowercased()
        let action = extracted.action.lowercased()
        return existing.filter { task in
            guard task.type == type, task.status == .pending else { return false }
            let titleText = task.title.lowercased()
            let descText = task.description.lowercased()
            let targetHit = target.isEmpty == false && (titleText.contains(target) || descText.contains(target))
            let actionHit = action.isEmpty == false && (titleText.contains(action) || descText.contains(action))
            let repeatHit = extracted.timeInfo.period.isEmpty == false && mapRepeatType(period: extracted.timeInfo.period, frequency: extracted.timeInfo.frequency) == task.repeatType
            return targetHit || actionHit || repeatHit
        }
    }

    private func makeTaskTitle(extracted: TaskIntentExtraction, type: HealthTask.TaskType) -> String {
        if extracted.targetMetric.isEmpty == false {
            return extracted.targetMetric
        }
        switch type {
        case .medical: return "健康指标任务"
        case .exercise: return "运动任务"
        case .diet: return "饮食任务"
        }
    }

    private func makeTaskDescription(extracted: TaskIntentExtraction, type: HealthTask.TaskType) -> String {
        let action = extracted.action.isEmpty ? defaultAction(for: type) : extracted.action
        let metric = extracted.targetMetric.isEmpty ? defaultMetric(for: type) : extracted.targetMetric
        let intensity = extracted.intensityOrValue.isEmpty ? defaultIntensity(for: type) : extracted.intensityOrValue
        let frequency = extracted.timeInfo.frequency.isEmpty ? defaultFrequency(for: type) : extracted.timeInfo.frequency
        return "目标：\(metric)\n动作：\(action)\n计划：\(frequency)\n强度：\(intensity)"
    }

    private func defaultMetric(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return "健康指标稳定"
        case .exercise: return "活动量提升"
        case .diet: return "饮食控制"
        }
    }

    private func defaultAction(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return "定时监测"
        case .exercise: return "中等强度运动"
        case .diet: return "控制高糖高脂摄入"
        }
    }

    private func defaultIntensity(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return "每天 2 次"
        case .exercise: return "30 分钟"
        case .diet: return "每日热量控制"
        }
    }

    private func defaultFrequency(for type: HealthTask.TaskType) -> String {
        switch type {
        case .medical, .exercise, .diet:
            return "daily"
        }
    }

    private func resolveDueDate(startAt: Date, repeatType: HealthTask.RepeatType) -> Date? {
        switch repeatType {
        case .none:
            return Calendar.current.date(byAdding: .day, value: 1, to: startAt)
        case .daily:
            return Calendar.current.date(byAdding: .day, value: 1, to: startAt)
        case .weekly:
            return Calendar.current.date(byAdding: .day, value: 7, to: startAt)
        }
    }

    private func mapTaskType(_ value: String) -> HealthTask.TaskType {
        switch value.lowercased() {
        case "medical": return .medical
        case "exercise": return .exercise
        case "diet": return .diet
        default: return .medical
        }
    }

    private func mapRepeatType(period: String, frequency: String) -> HealthTask.RepeatType {
        let p = period.lowercased()
        let f = frequency.lowercased()
        if p.contains("week") || f.contains("每周") || f.contains("weekly") {
            return .weekly
        }
        if p.contains("day") || f.contains("每天") || f.contains("daily") {
            return .daily
        }
        return .none
    }

    private func buildTaskPayloadStrings(
        memberID: Int,
        type: HealthTask.TaskType,
        extracted: TaskIntentExtraction,
        startAt: Date,
        dueAt: Date?,
        repeatType: HealthTask.RepeatType,
        priority: HealthTask.Priority
    ) -> [String: String] {
        let base: [String: Any] = [
            "member_id": memberID,
            "creator_id": "current_user",
            "type": type.rawValue,
            "status": HealthTask.TaskStatus.pending.rawValue,
            "repeat_type": repeatType.rawValue,
            "priority": priority.rawValue,
            "source": HealthTask.Source.ai.rawValue,
            "start_time": iso8601(startAt),
            "due_time": dueAt.map(iso8601) ?? ""
        ]
        var payload: [String: String] = [
            "task": jsonString(from: base) ?? "{}"
        ]
        let reminder = reminderTimeString(from: extracted, fallback: startAt)
        switch type {
        case .medical:
            payload["task_medical"] = jsonString(from: [
                "medical_task_type": extracted.targetMetric.isEmpty ? "health_monitoring" : extracted.targetMetric,
                "description": extracted.action.isEmpty ? defaultAction(for: .medical) : extracted.action,
                "reminder_time": reminder
            ]) ?? "{}"
        case .exercise:
            let durationMin = parseIntValue(extracted.intensityOrValue) ?? 30
            payload["task_exercise"] = jsonString(from: [
                "exercise_type": extracted.action.isEmpty ? defaultAction(for: .exercise) : extracted.action,
                "duration_min": durationMin,
                "intensity": "medium",
                "description": extracted.targetMetric.isEmpty ? defaultMetric(for: .exercise) : extracted.targetMetric
            ]) ?? "{}"
        case .diet:
            let calorieTarget = parseIntValue(extracted.intensityOrValue) ?? 1800
            payload["task_diet"] = jsonString(from: [
                "meal_type": "dinner",
                "calorie_target": calorieTarget,
                "description": extracted.action.isEmpty ? defaultAction(for: .diet) : extracted.action,
                "food_recommend": extracted.targetMetric.isEmpty ? defaultMetric(for: .diet) : extracted.targetMetric,
                "reminder_time": reminder
            ]) ?? "{}"
        }
        return payload
    }

    private func reminderTimeString(from extracted: TaskIntentExtraction, fallback: Date) -> String {
        if let parsed = parseISODate(extracted.timeInfo.startTime) {
            return iso8601Minute(parsed)
        }
        return iso8601Minute(fallback)
    }

    private func parseIntValue(_ text: String) -> Int? {
        let pattern = #"[0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 0), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private func jsonString(from object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }

    private func parseISODate(_ text: String) -> Date? {
        guard text.isEmpty == false else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private func parseBool(_ text: String?, defaultValue: Bool) -> Bool {
        guard let text else { return defaultValue }
        switch text.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return defaultValue
        }
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func iso8601Minute(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// 解析任务归属成员：优先显式 member_id，其次当前成员；都没有时回退首个成员。
    private func resolveTargetMemberID(invocation: ToolInvocation, context: ToolExecutionContext) async -> Int? {
        if let value = invocation.arguments["member_id"], let explicit = Int(value) {
            return explicit
        }
        if let current = context.memberID {
            return current
        }
        if let members = try? await medicalQueryAPI.listMembers(),
           let first = members.first {
            return first.id
        }
        return nil
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return nil
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
        let snapshot = await aiConfigCenter.currentSnapshot()
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

private struct TaskQueryToolPayload: Encodable {
    let ok: Bool
    let memberID: Int
    let queriedAt: String
    let total: Int
    let tasks: [HealthTask]

    enum CodingKeys: String, CodingKey {
        case ok
        case memberID = "member_id"
        case queriedAt = "queried_at"
        case total
        case tasks
    }
}

private struct TaskNoCreateToolPayload: Encodable {
    let ok: Bool
    let action: String
    let reason: String
    let queriedFirst: Bool
    let memberID: Int
    let extracted: TaskIntentExtraction
    let similarTasks: [TaskSimilarityItem]

    enum CodingKeys: String, CodingKey {
        case ok
        case action
        case reason
        case queriedFirst = "queried_first"
        case memberID = "member_id"
        case extracted
        case similarTasks = "similar_tasks"
    }
}

private struct TaskSimilarityItem: Encodable {
    let taskID: Int
    let title: String
    let type: Int
    let status: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case title
        case type
        case status
        case updatedAt = "updated_at"
    }
}

private struct TaskCardToolWrapper: Encodable {
    let taskCards: [TaskToolCardPayload]

    enum CodingKeys: String, CodingKey {
        case taskCards = "task_cards"
    }
}

private struct TaskToolCardPayload: Encodable {
    let id: Int
    let member: Int
    let creator: Int?
    let title: String
    let description: String
    let type: Int
    let startTime: String?
    let dueTime: String?
    let repeatType: Int
    let priority: Int
    let businessType: String
    let businessID: String
    let source: Int
    let status: Int
    let extractPayload: [String: String]
    let taskPayload: [String: String]
    let similarityPayload: [String: String]
    let ignoredReason: String
    let confirmedTask: Int?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case member
        case creator
        case title
        case description
        case type
        case startTime = "start_time"
        case dueTime = "due_time"
        case repeatType = "repeat_type"
        case priority
        case businessType = "business_type"
        case businessID = "business_id"
        case source
        case status
        case extractPayload = "extract_payload"
        case taskPayload = "task_payload"
        case similarityPayload = "similarity_payload"
        case ignoredReason = "ignored_reason"
        case confirmedTask = "confirmed_task"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct TaskIntentExtraction: Codable {
    struct TimeInfo: Codable {
        let startTime: String
        let frequency: String
        let period: String

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case frequency
            case period
        }

        init(startTime: String, frequency: String, period: String) {
            self.startTime = startTime
            self.frequency = frequency
            self.period = period
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? ""
            frequency = try c.decodeIfPresent(String.self, forKey: .frequency) ?? ""
            period = try c.decodeIfPresent(String.self, forKey: .period) ?? ""
        }
    }

    let taskType: String
    let targetMetric: String
    let timeInfo: TimeInfo
    let action: String
    let intensityOrValue: String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case taskType = "task_type"
        case targetMetric = "target_metric"
        case timeInfo = "time_info"
        case action
        case intensityOrValue = "intensity_or_value"
        case confidence
    }

    init(
        taskType: String,
        targetMetric: String,
        timeInfo: TimeInfo,
        action: String,
        intensityOrValue: String,
        confidence: Double
    ) {
        self.taskType = taskType
        self.targetMetric = targetMetric
        self.timeInfo = timeInfo
        self.action = action
        self.intensityOrValue = intensityOrValue
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskType = try c.decodeIfPresent(String.self, forKey: .taskType) ?? "unknown"
        targetMetric = try c.decodeIfPresent(String.self, forKey: .targetMetric) ?? ""
        timeInfo = try c.decodeIfPresent(TimeInfo.self, forKey: .timeInfo) ?? .init(startTime: "", frequency: "", period: "")
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
        intensityOrValue = try c.decodeIfPresent(String.self, forKey: .intensityOrValue) ?? ""
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
    }

    func normalized() -> TaskIntentExtraction {
        TaskIntentExtraction(
            taskType: taskType.trimmingCharacters(in: .whitespacesAndNewlines),
            targetMetric: targetMetric.trimmingCharacters(in: .whitespacesAndNewlines),
            timeInfo: .init(
                startTime: timeInfo.startTime.trimmingCharacters(in: .whitespacesAndNewlines),
                frequency: timeInfo.frequency.trimmingCharacters(in: .whitespacesAndNewlines),
                period: timeInfo.period.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            action: action.trimmingCharacters(in: .whitespacesAndNewlines),
            intensityOrValue: intensityOrValue.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: confidence
        )
    }

    func asStringMap() -> [String: String] {
        [
            "task_type": taskType,
            "target_metric": targetMetric,
            "start_time": timeInfo.startTime,
            "frequency": timeInfo.frequency,
            "period": timeInfo.period,
            "action": action,
            "intensity_or_value": intensityOrValue,
            "confidence": String(format: "%.2f", confidence)
        ]
    }

    static func ruleBased(from input: String) -> TaskIntentExtraction {
        let text = input.lowercased()
        let type: String
        if text.contains("血糖") || text.contains("血压") || text.contains("服药") || text.contains("复诊") {
            type = "medical"
        } else if text.contains("步") || text.contains("运动") || text.contains("跑步") || text.contains("walk") {
            type = "exercise"
        } else if text.contains("饮食") || text.contains("热量") || text.contains("减脂") || text.contains("diet") {
            type = "diet"
        } else {
            type = "unknown"
        }
        return TaskIntentExtraction(
            taskType: type,
            targetMetric: extractTargetMetric(from: input),
            timeInfo: .init(
                startTime: "",
                frequency: extractFrequency(from: input),
                period: ""
            ),
            action: extractAction(from: input),
            intensityOrValue: extractIntensity(from: input),
            confidence: 0.55
        )
    }

    private static func extractTargetMetric(from text: String) -> String {
        let candidates = ["血糖", "血压", "体重", "步数", "热量", "饮食控制", "减脂"]
        return candidates.first(where: { text.contains($0) }) ?? ""
    }

    private static func extractAction(from text: String) -> String {
        let candidates = ["测量", "监测", "步行", "跑步", "运动", "控制饮食", "复诊", "服药"]
        return candidates.first(where: { text.contains($0) }) ?? ""
    }

    private static func extractFrequency(from text: String) -> String {
        if text.contains("每天") { return "daily" }
        if text.contains("每周") { return "weekly" }
        return ""
    }

    private static func extractIntensity(from text: String) -> String {
        let pattern = #"([0-9]+(\.[0-9]+)?\s*(次|步|分钟|分|km|公里|kcal|千卡))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return ""
        }
        return String(text[range])
    }
}
