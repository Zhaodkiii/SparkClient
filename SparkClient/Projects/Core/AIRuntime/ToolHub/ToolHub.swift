import Foundation

/// 聊天侧工具中枢：解析用户输入中的斜杠命令与 `SparkToolName`，执行后写审计；部分为占位或与配置中的外部 endpoint 路由说明。
final class ToolHub: @unchecked Sendable {
    let chatRepository: any ChatRepository
    let auditStore: ToolAuditStore
    let medicalQueryAPI: SparkMedicalQueryAPI
    let aiSettingsRepository: any AISettingsRepository
    let aiConfigCenter: AIConfigCenter
    let runtimeService: any AIRuntimeServing
    let taskService: TaskService
    let saveMemoryUseCase: SaveMemoryUseCase
    let retrieveMemoryUseCase: RetrieveMemoryUseCase
    let updateMemoryUseCase: UpdateMemoryUseCase
    let memoryPreferencesUseCase: MemoryPreferencesUseCase
    /// 知识库检索/创建：经用例访问 `CoreDataKnowledgeRepository`，避免在此直接操作持久化。
    let searchKnowledgeUseCase: SearchKnowledgeUseCase
    let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    /// 与上传流水线共用：对话工具 `generate_structured_health_card` 的结构化抽取。
    let typedMedicalDocumentExtractor: DefaultTypedMedicalDocumentExtractor
    /// 工具异步任务向助手消息落库 UI 副作用（经 `MessageRunActor` 串行写入）。
    let sideEffectSink: any ChatSideEffectSink
    let healthTool: SparkHealthTool
    let toolInteractionCoordinator: ToolInteractionCoordinator?
    let healthResourceToolService: any HealthResourceToolService
    let appleHealthToolConsentPolicy: AppleHealthToolConsentPolicy
    let webSearchGateway: WebSearchGateway
    let logger: Logger

    /// 内存画布：标题 → 正文（`createCanvas` / `editCanvas` 使用，进程内有效）。
    var canvasStore: [String: String] = [:]

    init(
        chatRepository: any ChatRepository,
        auditStore: ToolAuditStore,
        medicalQueryAPI: SparkMedicalQueryAPI,
        aiSettingsRepository: any AISettingsRepository,
        aiConfigCenter: AIConfigCenter,
        runtimeService: any AIRuntimeServing,
        taskService: TaskService,
        saveMemoryUseCase: SaveMemoryUseCase,
        retrieveMemoryUseCase: RetrieveMemoryUseCase,
        updateMemoryUseCase: UpdateMemoryUseCase,
        memoryPreferencesUseCase: MemoryPreferencesUseCase,
        searchKnowledgeUseCase: SearchKnowledgeUseCase,
        createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase,
        typedMedicalDocumentExtractor: DefaultTypedMedicalDocumentExtractor,
        sideEffectSink: any ChatSideEffectSink,
        healthTool: SparkHealthTool = .shared,
        toolInteractionCoordinator: ToolInteractionCoordinator? = nil,
        healthResourceToolService: (any HealthResourceToolService)? = nil,
        appleHealthToolConsentPolicy: AppleHealthToolConsentPolicy = AppleHealthToolConsentPolicy(),
        webSearchGateway: WebSearchGateway = WebSearchGateway(),
        logger: Logger = ConsoleLogger()
    ) {
        self.chatRepository = chatRepository
        self.auditStore = auditStore
        self.medicalQueryAPI = medicalQueryAPI
        self.aiSettingsRepository = aiSettingsRepository
        self.aiConfigCenter = aiConfigCenter
        self.runtimeService = runtimeService
        self.taskService = taskService
        self.saveMemoryUseCase = saveMemoryUseCase
        self.retrieveMemoryUseCase = retrieveMemoryUseCase
        self.updateMemoryUseCase = updateMemoryUseCase
        self.memoryPreferencesUseCase = memoryPreferencesUseCase
        self.searchKnowledgeUseCase = searchKnowledgeUseCase
        self.createKnowledgeDocumentUseCase = createKnowledgeDocumentUseCase
        self.typedMedicalDocumentExtractor = typedMedicalDocumentExtractor
        self.sideEffectSink = sideEffectSink
        self.healthTool = healthTool
        self.toolInteractionCoordinator = toolInteractionCoordinator
        self.healthResourceToolService = healthResourceToolService
            ?? DefaultHealthResourceToolService(medicalQueryAPI: medicalQueryAPI)
        self.appleHealthToolConsentPolicy = appleHealthToolConsentPolicy
        self.webSearchGateway = webSearchGateway
        self.logger = logger
    }

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

    /// `/audit_tools`：打印最近审计事件摘要。
    func handleAuditTools() async -> ToolHubResult {
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

    /// 与 HealthClient `ZDKOpenChatTools` 一致：工具文案键为 `ToolPrompts.strings` 中的 `tool.*`。
    func toolFormat(_ key: String, _ args: CVarArg...) -> String {
        let template = AIPromptL10n(locale: .current).tool(key)
        return String(format: template, locale: Locale.current, arguments: Array(args))
    }

    func td(_ key: String) -> String {
        AIPromptL10n(locale: .current).tool(key)
    }

    func coordPropertySchema() -> AIRuntimeToolProperty {
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

    func dateRangeProperties() -> [String: AIRuntimeToolProperty] {
        [
            "start_date": AIRuntimeToolProperty(type: "string", description: td("tool.date.start_yyyy_mm_dd"), format: "date"),
            "end_date": AIRuntimeToolProperty(type: "string", description: td("tool.date.end_yyyy_mm_dd"), format: "date")
        ]
    }

    /// key 规则统一为 `"tool.summary.<tool_name>"`，直接插值，无需逐 case 列举。
    func toolSummary(for toolName: String) -> String {
        td("tool.summary.\(toolName)")
    }

    /// 穷举 switch，新增工具时编译器会强制要求补全此处，无 default 兜底。
    func toolProperties(for toolName: String) -> [String: AIRuntimeToolProperty] {
        guard let tool = SparkToolName(rawValue: toolName) else {
            return ["query": AIRuntimeToolProperty(type: "string", description: td("tool.param.tool_query_generic"))]
        }
        let coord = coordPropertySchema()
        switch tool {
        case .fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails, .fetchSleepDetails:
            return dateRangeProperties()
        case .makeNutritionData:
            return [
                "protein": AIRuntimeToolProperty(type: "number", description: td("tool.param.protein_g")),
                "carbohydrates": AIRuntimeToolProperty(type: "number", description: td("tool.param.carbohydrates_g")),
                "fat": AIRuntimeToolProperty(type: "number", description: td("tool.param.fat_g")),
                "energy": AIRuntimeToolProperty(type: "number", description: td("tool.param.energy_kcal"))
            ]
        case .fetchWorkoutDetails:
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
        case .listMemberHealthSources:
            return [
                "member_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.member_id_optional")),
                "resource_type": healthResourceTypeProperty(),
                "resource_types": healthResourceTypesProperty(),
                "keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.health_keyword")),
                "start_date": AIRuntimeToolProperty(type: "string", description: td("tool.date.start_yyyy_mm_dd"), format: "date"),
                "end_date": AIRuntimeToolProperty(type: "string", description: td("tool.date.end_yyyy_mm_dd"), format: "date"),
                "limit": AIRuntimeToolProperty(type: "integer", description: td("tool.param.health_sources_limit"))
            ]
        case .getHealthResourceReference, .getHealthResourceContext:
            var props: [String: AIRuntimeToolProperty] = [
                "resource_type": healthResourceTypeProperty(),
                "resource_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.health_resource_id")),
                "member_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.member_id_optional"))
            ]
            if tool == .getHealthResourceContext {
                props["topic"] = AIRuntimeToolProperty(type: "string", description: td("tool.param.health_topic_focus"))
                props["references"] = AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.health_references_json")
                )
            }
            return props
        case .generateStructuredHealthCard:
            return [
                "report_type": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.report_type_enum"),
                    enumValues: [
                        "medication_plan",
                        "medicine_box",
                        "prescription",
                        "exam_report",
                        "medical_case"
                    ]
                ),
                "raw_text": AIRuntimeToolProperty(type: "string", description: td("tool.param.raw_text_distilled")),
                "oss_file_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.oss_file_id_optional"))
            ]
        case .queryTasksByMember:
            return [
                "member_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.member_id_for_task")),
                "include_completed": AIRuntimeToolProperty(type: "boolean", description: td("tool.param.include_completed_optional")),
                "limit": AIRuntimeToolProperty(type: "integer", description: td("tool.param.max_items"))
            ]
        case .generateTask:
            return [
                "member_id": AIRuntimeToolProperty(type: "integer", description: td("tool.param.member_id_for_task")),
                "user_input": AIRuntimeToolProperty(type: "string", description: td("tool.param.user_input_for_extraction")),
                "require_query_first": AIRuntimeToolProperty(type: "boolean", description: td("tool.param.require_query_first"))
            ]
        case .searchKnowledgeBag:
            return ["query": AIRuntimeToolProperty(type: "string", description: td("tool.param.query_keyword"))]
        case .createKnowledgeDocument:
            return [
                "title": AIRuntimeToolProperty(type: "string", description: td("tool.param.doc_title")),
                "content": AIRuntimeToolProperty(type: "string", description: td("tool.param.doc_content_markdown"))
            ]
        case .searchCalendarAndReminders:
            return [
                "keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.keyword_title_notes")),
                "start_date": AIRuntimeToolProperty(type: "string", description: td("tool.param.start_date_inclusive"), format: "date"),
                "end_date": AIRuntimeToolProperty(type: "string", description: td("tool.param.end_date_inclusive"), format: "date"),
                "location": AIRuntimeToolProperty(type: "string", description: td("tool.param.location_keyword")),
                "event_type": AIRuntimeToolProperty(type: "string", description: td("tool.param.calendar_or_reminder_enum"), enumValues: ["calendar", "reminder"])
            ]
        case .writeSystemEvent:
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
        case .queryLocation:
            return ["keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.place_keyword"))]
        case .getCurrentLocation:
            return ["query": AIRuntimeToolProperty(type: "string", description: td("tool.param.query_fixed_local"), enumValues: ["local"])]
        case .searchNearbyLocations:
            return [
                "coordinate": coord,
                "keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.search_keyword_poi"))
            ]
        case .getRoute:
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
        case .queryWeather:
            return [
                "latitude": AIRuntimeToolProperty(type: "number", description: td("tool.param.latitude")),
                "longitude": AIRuntimeToolProperty(type: "number", description: td("tool.param.longitude")),
                "timeRange": AIRuntimeToolProperty(type: "string", description: td("tool.param.weather_time_range"))
            ]
        case .saveMemory:
            return ["content": AIRuntimeToolProperty(type: "string", description: td("tool.param.memory_content"))]
        case .retrieveMemory:
            return ["keyword": AIRuntimeToolProperty(type: "string", description: td("tool.param.memory_keywords"))]
        case .updateMemory:
            return [
                "originalContent": AIRuntimeToolProperty(type: "string", description: td("tool.param.memory_original")),
                "updatedContent": AIRuntimeToolProperty(type: "string", description: td("tool.param.memory_updated"))
            ]
        case .requestMemberSelection:
            return ["reason": AIRuntimeToolProperty(type: "string", description: td("tool.param.member_selection_reason"))]
        case .generateChatTitle, .getCurrentMember, .switchMember:
            return [:]
        case .showCustomMessageCard:
            return [
                "card_type": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.attachment_types"),
                    enumValues: ["report_photo", "medicine_box_photo", "skin_photo"]
                )
            ]
        case .findMember:
            return [
                "name": AIRuntimeToolProperty(type: "string", description: td("tool.param.member_name_optional")),
                "relationship": AIRuntimeToolProperty(type: "string", description: td("tool.param.member_relationship_optional"))
            ]
        case .queryMemberProfile:
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
        case .searchOnline, .searchArxivPapers:
            return ["query": AIRuntimeToolProperty(type: "string", description: td("tool.param.search_query"))]
        case .readWebPage, .extractRemoteFileContent:
            return ["url": AIRuntimeToolProperty(type: "string", description: td("tool.param.url_full"))]
        case .createCanvas:
            return [
                "title": AIRuntimeToolProperty(type: "string", description: td("tool.param.canvas_title")),
                "content": AIRuntimeToolProperty(type: "string", description: td("tool.param.canvas_body")),
                "type": AIRuntimeToolProperty(type: "string", description: td("tool.param.canvas_type_enum"), enumValues: ["text", "python", "html"])
            ]
        case .editCanvas:
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
        case .askUserQuestion:
            return [
                "question": AIRuntimeToolProperty(type: "string", description: td("tool.param.ask_user_question")),
                "questions": AIRuntimeToolProperty(
                    type: "array",
                    description: td("tool.param.ask_user_questions"),
                    arrayItems: AIRuntimeToolProperty(type: "object", description: td("tool.param.ask_user_question_item"))
                ),
                "options": AIRuntimeToolProperty(
                    type: "array",
                    description: td("tool.param.ask_user_options"),
                    arrayItems: AIRuntimeToolProperty(type: "string", description: td("tool.param.ask_user_option_item"))
                ),
                "selection_mode": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.ask_user_selection_mode"),
                    enumValues: ["single", "multiple"]
                ),
                "allows_other": AIRuntimeToolProperty(type: "boolean", description: td("tool.param.ask_user_allows_other"))
            ]
        }
    }

    /// 穷举 switch，新增工具时编译器会强制要求补全此处，无 default 兜底。
    func toolRequiredFields(for toolName: String) -> [String] {
        guard let tool = SparkToolName(rawValue: toolName) else { return [] }
        switch tool {
        case .fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails,
             .fetchSleepDetails, .fetchWorkoutDetails:
            return ["start_date", "end_date"]
        case .makeNutritionData:
            return ["protein", "carbohydrates", "fat", "energy"]
        case .generateStructuredHealthCard:
            return ["report_type", "raw_text"]
        case .getHealthResourceReference:
            return ["resource_type", "resource_id"]
        case .getHealthResourceContext:
            return []
        case .generateTask:
            return ["user_input"]
        case .searchKnowledgeBag:
            return ["query"]
        case .createKnowledgeDocument:
            return ["title", "content"]
        case .queryLocation:
            return ["keyword"]
        case .getCurrentLocation:
            return ["query"]
        case .searchNearbyLocations:
            return ["coordinate", "keyword"]
        case .getRoute:
            return ["start", "end", "mode"]
        case .queryWeather:
            return ["latitude", "longitude", "timeRange"]
        case .saveMemory:
            return ["content"]
        case .retrieveMemory:
            return ["keyword"]
        case .updateMemory:
            return ["originalContent", "updatedContent"]
        case .showCustomMessageCard:
            return ["card_type"]
        case .askUserQuestion:
            return []
        case .queryMemberProfile:
            return ["query_type"]
        case .searchOnline, .searchArxivPapers:
            return ["query"]
        case .readWebPage, .extractRemoteFileContent:
            return ["url"]
        case .createCanvas:
            return ["title", "content", "type"]
        case .editCanvas:
            return ["patterns", "replacements"]
        case .listMemberHealthSources,
             .requestMemberSelection,
             .searchCalendarAndReminders, .writeSystemEvent,
             .queryTasksByMember, .generateChatTitle,
             .getCurrentMember, .switchMember, .findMember:
            return []
        }
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
    /// - 设计说明：
    ///   1. 这是 Tool 调度的统一入口（类似 Router / Dispatcher）
    ///   2. 所有工具调用最终都会进入这里，根据 `invocation.name` 分发
    ///   3. 大多数工具返回 `shouldBypassModel = true`：
    ///      表示「结果直接展示给用户」，无需再经过大模型润色
    ///   4. 少部分工具（如需要模型总结/解释）可以设为 false
    ///
    /// - 执行流程：
    ///   invocation.name -> 映射 SparkToolName -> switch -> runXXX
    ///
    /// - 扩展方式：
    ///   新增工具时：
    ///   1. 在 `SparkToolName` 中增加枚举
    ///   2. 在此 switch 中增加 case
    ///   3. 实现对应 runXXX 方法
    ///
    /// - 注意：
    ///   该方法是 async，允许工具内部执行 IO（网络 / DB / 本地存储）
    ///
    /// - Parameters:
    ///   - invocation: 工具调用请求（包含 name / 参数等）
    ///   - context: 执行上下文（线程ID、消息ID、用户态信息等）
    ///
    /// - Returns:
    ///   ToolExecutionResult：统一封装工具执行结果
    func execute(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) async -> ToolExecutionResult {

        // MARK: - 内置工具：tool_list（列出所有已接入工具）
        // 用于调试 / LLM 自省（让模型知道当前系统有哪些工具能力）
        if invocation.name == "tool_list" {
            return ToolExecutionResult(
                toolName: "tool_list",
                outputText: "已接入工具（\(SparkToolName.all.count)）：\n\(SparkToolName.all.joined(separator: "\n"))",
                sensitive: false,              // 非敏感信息，可直接展示
                shouldBypassModel: true        // 不需要模型再加工，直接展示
            )
        }

        // MARK: - 工具名解析（字符串 -> 强类型枚举）
        // 目的：避免 magic string，统一工具标识
        guard let tool = SparkToolName(rawValue: invocation.name) else {
            // 未识别工具：直接返回错误信息（不中断流程）
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "未识别工具：\(invocation.name)",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        // MARK: - 工具分发（核心路由逻辑）
        switch tool {

        // MARK: ===== 健康数据类工具 =====
        case .fetchStepDetails:
            /// 获取步数详情（如每日步数、趋势等）
            return await runFetchSteps(invocation: invocation)

        case .fetchSleepDetails:
            /// 获取睡眠数据（需要 context，可能涉及用户身份）
            return await runFetchSleep(invocation: invocation, context: context)

        case .fetchEnergyDetails:
            /// 获取能量消耗（卡路里等）
            return await runFetchEnergy(invocation: invocation)

        case .fetchNutritionDetails:
            /// 获取营养摄入（蛋白质 / 脂肪 / 碳水等）
            return await runFetchNutrition(invocation: invocation)

        case .fetchWorkoutDetails:
            /// 获取运动记录（类型、时长、强度等）
            return await runFetchWorkout(invocation: invocation, context: context)

        case .makeNutritionData:
            /// 构建营养数据并在对话内插入营养卡片
            return runMakeNutritionData(invocation: invocation, context: context)


        // MARK: ===== 知识库类工具 =====
        case .searchKnowledgeBag:
            /// 搜索知识库（可能涉及向量检索 / 语义搜索）
            return await runSearchKnowledgeBag(invocation: invocation, context: context)

        case .createKnowledgeDocument:
            /// 创建知识文档（写入知识库）
            return await runCreateKnowledgeDocument(invocation: invocation, context: context)


        // MARK: ===== Memory（长期记忆）工具 =====
        case .saveMemory:
            /// 保存记忆（用户偏好 / 历史信息）
            return await runSaveMemory(invocation: invocation)

        case .retrieveMemory:
            /// 读取记忆
            return await runRetrieveMemory(invocation: invocation)

        case .updateMemory:
            /// 更新已有记忆
            return await runUpdateMemory(invocation: invocation)


        // MARK: ===== Member（多用户 / 家庭成员）相关 =====
        case .getCurrentMember:
            /// 获取当前选中的成员
            return await runGetCurrentMember(context: context)

        case .requestMemberSelection:
            /// 请求用户选择成员（通常会触发 UI 卡片交互）
            return await runRequestMemberSelection(invocation: invocation, context: context)

        case .switchMember, .findMember:
            /// 切换或查找成员（合并处理）
            return await runFindMember(invocation: invocation)

        case .queryMemberProfile:
            /// 查询成员详细信息（健康档案等）
            return await runQueryMemberProfile(invocation: invocation, context: context)


        // MARK: ===== AI 生成类 =====
        case .generateStructuredHealthCard:
            /// 生成结构化健康卡片（可能结合模型推理 + 数据）
            return await runGenerateStructuredHealthCard(invocation: invocation, context: context)

        case .listMemberHealthSources:
            return await runListMemberHealthSources(invocation: invocation, context: context)

        case .getHealthResourceReference:
            return await runGetHealthResourceReference(invocation: invocation, context: context)

        case .getHealthResourceContext:
            return await runGetHealthResourceContext(invocation: invocation, context: context)

        case .queryTasksByMember:
            /// 查询某成员的小任务列表
            return await runQueryTasksByMember(invocation: invocation, context: context)

        case .generateTask:
            /// AI 生成小任务（基于用户目标/状态）
            return await runGenerateTask(invocation: invocation, context: context)

        case .generateChatTitle:
            /// 生成聊天标题（轻量级，无需 async）
            return runGenerateChatTitle(invocation: invocation)

        case .createCanvas:
            /// 创建画布（如笔记 / 可视化区域）
            return runCreateCanvas(invocation: invocation)

        case .editCanvas:
            /// 编辑画布内容
            return runEditCanvas(invocation: invocation)


        // MARK: ===== UI 卡片类 =====
        case .showCustomMessageCard:
            /// 展示自定义消息卡片（强 UI 交互）
            return await runShowCustomMessageCard(invocation: invocation, context: context)

        case .askUserQuestion:
            /// 回调 UI 弹出问题 sheet，用户提交后继续工具循环。
            return await runAskUserQuestion(invocation: invocation, context: context)


        // MARK: ===== 外部连接器（统一出口） =====
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

            /// 所有外部能力统一走 Connector 层：
            /// - 优点：统一鉴权 / 限流 / 日志 / 错误处理
            /// - 避免每个工具重复实现 HTTP / SDK 逻辑
            return await runExternalConnectorTool(invocation: invocation, context: context)
        }
    }

    func applyModelEgressConsentIfNeeded(
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        result: ToolExecutionResult
    ) async -> ToolExecutionResult {
        guard appleHealthToolConsentPolicy.requiresConsent(
            result: result,
            providerCompany: context.providerCompany
        ) else {
            return result
        }
        guard let toolInteractionCoordinator else {
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: "当前界面无法展示授权弹窗，已阻止敏感工具结果发送给模型。"
            )
        }

        let callArguments = encodeJSON(invocation.arguments) ?? invocation.arguments.description
        let decision = await toolInteractionCoordinator.requestConsentDecision(
            threadID: context.threadID,
            result: result,
            callArguments: callArguments,
            providerCompany: context.providerCompany,
            modelName: context.modelName,
            endpoint: context.endpoint,
            privacyPolicyURL: context.privacyPolicyURL
        )
        switch decision {
        case .success(let decision):
            guard decision.allowed else {
                return modelEgressDeniedResult(
                    toolName: result.toolName,
                    reason: "用户未授权将该工具结果发送给第三方模型。"
                )
            }
            if decision.rememberTool {
                appleHealthToolConsentPolicy.rememberAllowed(toolName: result.toolName)
            }
            return result
        case .cancelled:
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: "用户未授权将该工具结果发送给第三方模型。"
            )
        case .conflict:
            return modelEgressDeniedResult(
                toolName: result.toolName,
                reason: "授权交互繁忙，已阻止敏感工具结果发送给模型。"
            )
        }
    }

    func modelEgressDeniedResult(toolName: String, reason: String) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            outputText: PromptLocalizer().consentBlockedHint(reason: reason),
            sensitive: false,
            shouldBypassModel: true
        )
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

    /// 将本次工具调用写入审计存储，并按输出是否含「失败」粗判状态。
    func appendAudit(
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

    func shortID(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }
}
