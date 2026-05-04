import Foundation

/// 聊天侧工具中枢：解析用户输入中的斜杠命令与 `SparkToolName`，执行后写审计；部分为占位或与配置中的外部 endpoint 路由说明。
final class ToolHub: @unchecked Sendable {
    private let chatRepository: any ChatRepository
    private let auditStore: ToolAuditStore
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let aiSettingsRepository: any AISettingsRepository
    private let aiConfigCenter: AIConfigCenter
    private let runtimeService: any AIRuntimeServing
    private let taskService: TaskService
    private let saveMemoryUseCase: SaveMemoryUseCase
    private let retrieveMemoryUseCase: RetrieveMemoryUseCase
    private let updateMemoryUseCase: UpdateMemoryUseCase
    private let memoryPreferencesUseCase: MemoryPreferencesUseCase
    /// 知识库检索/创建：经用例访问 `CoreDataKnowledgeRepository`，避免在此直接操作持久化。
    private let searchKnowledgeUseCase: SearchKnowledgeUseCase
    private let createKnowledgeDocumentUseCase: CreateKnowledgeDocumentUseCase
    /// 与上传流水线共用：对话工具 `generate_structured_health_card` 的结构化抽取。
    private let typedMedicalDocumentExtractor: DefaultTypedMedicalDocumentExtractor
    /// 异步将卡片合并回当前助手消息（Core Data + `ChatStateStore`）。
    private let structuredHealthCardMergeCoordinator: StructuredHealthCardMergeCoordinator
    private let healthTool: SparkHealthTool
    private let toolInteractionCoordinator: ToolInteractionCoordinator?
    private let appleHealthToolConsentPolicy: AppleHealthToolConsentPolicy
    private let webSearchGateway: WebSearchGateway
    private let logger: Logger

    /// 内存画布：标题 → 正文（`createCanvas` / `editCanvas` 使用，进程内有效）。
    private var canvasStore: [String: String] = [:]

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
        structuredHealthCardMergeCoordinator: StructuredHealthCardMergeCoordinator,
        healthTool: SparkHealthTool = .shared,
        toolInteractionCoordinator: ToolInteractionCoordinator? = nil,
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
        self.structuredHealthCardMergeCoordinator = structuredHealthCardMergeCoordinator
        self.healthTool = healthTool
        self.toolInteractionCoordinator = toolInteractionCoordinator
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

    /// key 规则统一为 `"tool.summary.<tool_name>"`，直接插值，无需逐 case 列举。
    private func toolSummary(for toolName: String) -> String {
        td("tool.summary.\(toolName)")
    }

    /// 穷举 switch，新增工具时编译器会强制要求补全此处，无 default 兜底。
    private func toolProperties(for toolName: String) -> [String: AIRuntimeToolProperty] {
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
        case .generateStructuredHealthCard:
            return [
                "report_type": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.report_type_enum"),
                    enumValues: ["medication", "prescription", "exam_report", "medical_case"]
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
    private func toolRequiredFields(for toolName: String) -> [String] {
        guard let tool = SparkToolName(rawValue: toolName) else { return [] }
        switch tool {
        case .fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails,
             .fetchSleepDetails, .fetchWorkoutDetails:
            return ["start_date", "end_date"]
        case .makeNutritionData:
            return ["protein", "carbohydrates", "fat", "energy"]
        case .generateStructuredHealthCard:
            return ["report_type", "raw_text"]
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
        case .requestMemberSelection,
             .searchCalendarAndReminders, .writeSystemEvent,
             .queryTasksByMember, .generateChatTitle,
             .getCurrentMember, .switchMember, .findMember:
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
    private func execute(
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
            /// 构建营养数据（纯计算逻辑，无需 async）
            return runMakeNutritionData(invocation: invocation)


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

    private func applyModelEgressConsentIfNeeded(
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

    private func modelEgressDeniedResult(toolName: String, reason: String) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            outputText: PromptLocalizer().consentBlockedHint(reason: reason),
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 从 HealthKit 查询真实步数和步行/跑步距离。
    private func runFetchSteps(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        return ToolExecutionResult(
            toolName: SparkToolName.fetchStepDetails,
            outputText: await healthTool.fetchStepDetails(from: range.start, to: range.end),
            sensitive: true,
            shouldBypassModel: true
        )
    }

    /// 从 HealthKit 查询真实睡眠阶段，并返回聊天卡片可解析的 `sleep_model`。
    private func runFetchSleep(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments, fallbackDays: 2)
        do {
            let model = try await healthTool.fetchSleepDetails(from: range.start, to: range.end)
            // 仅向模型提供可读摘要；完整结构由协调器异步写入 `healthSleepVisualization`，不经工具输出再解码。
            let outputText = model.toReadableText()
            if let threadID = context.threadID,
               let assistantID = context.assistantMessageClientID {
                let merge = structuredHealthCardMergeCoordinator
                let normalizedToolCallID = context.pendingToolCallID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await merge.insertHealthSleepVisualizationWhenAssistantMessageReady(
                        threadID: threadID,
                        assistantClientMessageID: assistantID,
                        model: model,
                        anchorToolCallID: (normalizedToolCallID?.isEmpty == false ? normalizedToolCallID : nil),
                        )
                }
            }
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: outputText,
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: "睡眠查询失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    private func runFetchEnergy(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        return ToolExecutionResult(
            toolName: SparkToolName.fetchEnergyDetails,
            outputText: await healthTool.fetchEnergyDetails(from: range.start, to: range.end),
            sensitive: true,
            shouldBypassModel: true
        )
    }

    private func runFetchNutrition(invocation: ToolInvocation) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        return ToolExecutionResult(
            toolName: SparkToolName.fetchNutritionDetails,
            outputText: await healthTool.fetchNutritionDetails(from: range.start, to: range.end),
            sensitive: true,
            shouldBypassModel: true
        )
    }

    private func runFetchWorkout(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let range = resolveHealthRange(arguments: invocation.arguments)
        let types = parseStringList(invocation.arguments["types"])
        let maxItems = parseIntValue(invocation.arguments["max_items"] ?? "") ?? 100
        do {
            let model = try await healthTool.fetchWorkoutDetails(from: range.start, to: range.end, types: types, maxItems: maxItems)
            if let threadID = context.threadID,
               let assistantID = context.assistantMessageClientID {
                let merge = structuredHealthCardMergeCoordinator
                let normalizedToolCallID = context.pendingToolCallID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await merge.insertHealthWorkoutVisualizationWhenAssistantMessageReady(
                        threadID: threadID,
                        assistantClientMessageID: assistantID,
                        model: model,
                        anchorToolCallID: (normalizedToolCallID?.isEmpty == false ? normalizedToolCallID : nil)
                    )
                }
            }
            return ToolExecutionResult(
                toolName: SparkToolName.fetchWorkoutDetails,
                outputText: model.toReadableText(),
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.fetchWorkoutDetails,
                outputText: "运动记录查询失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    private func runMakeNutritionData(invocation: ToolInvocation) -> ToolExecutionResult {
        let card = healthTool.makeNutritionData(
            protein: parseDoubleValue(invocation.arguments["protein"]),
            carbohydrates: parseDoubleValue(invocation.arguments["carbohydrates"]),
            fat: parseDoubleValue(invocation.arguments["fat"]),
            energy: parseDoubleValue(invocation.arguments["energy"])
        )
        let json = (try? JSONEncoder().encode(card))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{}"
        return ToolExecutionResult(
            toolName: SparkToolName.makeNutritionData,
            outputText: "nutrition_card=\(json)",
            sensitive: false,
            shouldBypassModel: true
        )
    }

    private func resolveHealthRange(arguments: [String: String], fallbackDays: Int = 0) -> (start: Date, end: Date) {
        let now = Date()
        let end = min(parseDate(arguments["end_date"]) ?? now, now)
        let start = parseDate(arguments["start_date"])
            ?? Calendar.current.date(byAdding: .day, value: -fallbackDays, to: end)
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

    private func parseDoubleValue(_ text: String?) -> Double? {
        guard let text else { return nil }
        return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseStringList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
        }
        return trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
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

    /// 在本地知识库中按标题、正文和切块检索知识片段；知识卡预览由协调器异步写入，不经 `ChatToolEventInterpreter`。
    private func runSearchKnowledgeBag(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
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
            let body = lines.joined(separator: "\n\n")
            let l10n = AIPromptL10n(locale: .current)
            let title = l10n.tool("tool.ui.knowledge.search_title", fallback: "Knowledge Search")
            if let threadID = context.threadID,
               let assistantID = context.assistantMessageClientID {
                let merge = structuredHealthCardMergeCoordinator
                let anchorToolCallID = normalizedToolCallID(from: context)
                Task {
                    await merge.insertKnowledgeCardsWhenAssistantMessageReady(
                        threadID: threadID,
                        assistantClientMessageID: assistantID,
                        cards: [ChatKnowledgeCard(title: title, content: body, showsSaveAndCopy: false)],
                        anchorToolCallID: anchorToolCallID
                    )
                }
            }
            return ToolExecutionResult(
                toolName: SparkToolName.searchKnowledgeBag,
                outputText: body,
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

    /// 生成知识文档草稿（消息内知识卡由协调器异步合并）；向模型仅返回可读说明，不依赖发送链路解析 `knowledge_card`。
    private func runCreateKnowledgeDocument(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
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
        let resolvedTitle = title.isEmpty ? "未命名文档" : title
        logger.info(
            "create_knowledge_document 生成预览草稿，title=\(resolvedTitle), contentLength=\(content.count)",
            module: .aiConfig
        )

        let userFacing = "已生成知识库文档草稿「\(resolvedTitle)」，内容已附在消息内知识卡中，用户可点击保存到知识库。"
        if let threadID = context.threadID,
           let assistantID = context.assistantMessageClientID {
            let merge = structuredHealthCardMergeCoordinator
            let anchorToolCallID = normalizedToolCallID(from: context)
            Task {
                await merge.insertKnowledgeCardsWhenAssistantMessageReady(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    cards: [ChatKnowledgeCard(title: resolvedTitle, content: content)],
                    anchorToolCallID: anchorToolCallID
                )
            }
        }
        return ToolExecutionResult(
            toolName: SparkToolName.createKnowledgeDocument,
            outputText: userFacing,
            sensitive: false,
            shouldBypassModel: true
        )
    }

    /// 将内容写入独立记忆仓储。
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

        let preferences = await memoryPreferencesUseCase.load()
        guard preferences.isEnabled, preferences.allowToolWrite else {
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆功能当前未允许写入。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let record = try await saveMemoryUseCase.execute(content: content)
            return ToolExecutionResult(
                toolName: SparkToolName.saveMemory,
                outputText: "记忆已保存：\(record.title)",
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

    /// 无 query 时取最近几条记忆；有 query 时用记忆检索引擎召回。
    private func runRetrieveMemory(invocation: ToolInvocation) async -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["keyword"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let hits = try await retrieveMemoryUseCase.execute(keyword: query)
            if hits.isEmpty {
                return ToolExecutionResult(
                    toolName: SparkToolName.retrieveMemory,
                    outputText: "未检索到相关记忆。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
            let lines = hits.map { hit in
                "- \(hit.record.title)：\(hit.record.content)"
            }
            return ToolExecutionResult(
                toolName: SparkToolName.retrieveMemory,
                outputText: lines.joined(separator: "\n"),
                sensitive: true,
                shouldBypassModel: true
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.retrieveMemory,
                outputText: "记忆检索失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
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

        do {
            guard let record = try await updateMemoryUseCase.execute(
                originalContentOrTitle: original,
                updatedContent: updated
            ) else {
                return ToolExecutionResult(
                    toolName: SparkToolName.updateMemory,
                    outputText: "记忆更新失败：未找到原始内容。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
            return ToolExecutionResult(
                toolName: SparkToolName.updateMemory,
                outputText: "记忆已更新：\(record.title)",
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

    /// 模型主动请求用户选择成员：无成员时挂起当前工具循环，有成员时返回可继续推理的工具结果。
    private func runRequestMemberSelection(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        if let memberID = await resolveTargetMemberID(invocation: invocation, context: context) {
            return memberSelectionCompletedResult(toolName: SparkToolName.requestMemberSelection.rawValue, memberID: memberID)
        }
        let rawReason = invocation.arguments["reason"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = rawReason?.isEmpty == false ? rawReason : nil
        guard let selectedMemberID = await awaitMemberSelection(
            invocation: invocation,
            context: context,
            reason: reason ?? "request_member_selection"
        ) else {
            return memberSelectionTimeoutResult(toolName: SparkToolName.requestMemberSelection.rawValue)
        }
        return memberSelectionCompletedResult(toolName: SparkToolName.requestMemberSelection.rawValue, memberID: selectedMemberID)
    }

    private func memberSelectionCompletedResult(toolName: String, memberID: Int) -> ToolExecutionResult {
        let output = [
            td("tool.result.request_member_selection.completed"),
            #"{"selection_completed":true,"member_id":\#(memberID),"instruction":"continue_conversation"}"#
        ].joined(separator: "\n")
        return ToolExecutionResult(
            toolName: toolName,
            outputText: output,
            sensitive: false,
            shouldBypassModel: true,
            resolvedMemberID: memberID
        )
    }

    private func memberSelectionTimeoutResult(toolName: String) -> ToolExecutionResult {
        let output = [
            td("tool.result.request_member_selection.timeout"),
            #"{"selection_completed":false,"reason":"user_not_selected","instruction":"continue_without_member_or_ask_again"}"#
        ].joined(separator: "\n")
        return ToolExecutionResult(
            toolName: toolName,
            outputText: output,
            sensitive: false,
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

        let memberID: Int
        if let targetMemberID {
            memberID = targetMemberID
        } else if let selected = await awaitMemberSelection(
            invocation: invocation,
            context: context,
            reason: "query_member_profile"
        ) {
            memberID = selected
        } else {
            return memberSelectionTimeoutResult(toolName: SparkToolName.queryMemberProfile.rawValue)
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

    /// 对齐 HealthClient 规范：同步返回系统提示语，结构化健康卡片在后台抽取完成后，合并到当前助手消息中
    private func runGenerateStructuredHealthCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        // 获取对应语言的本地化文案
        let l10n = AIPromptL10n(locale: context.locale)
        
        // 生成模型提示文案：告知用户结构化卡片正在后台生成，无需等待，可继续对话
        let hintTemplate = l10n.tool(
            "tool.async.structured_health_card.model_hint",
            fallback: """
                [系统] 结构化健康卡片正在后台生成中。无需等待，可继续根据用户消息进行回复；卡片将展示在本条回复下方。
                """
        )
        
        // 解析报告类型：支持 report_type / category 两个参数名，统一做小写、去空格处理
        let reportType = (invocation.arguments["report_type"] ?? invocation.arguments["category"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        // 解析原始文本：支持 raw_text / content 两个参数名，去空格处理
        let rawText = (invocation.arguments["raw_text"] ?? invocation.arguments["content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 校验：原始文本为空，返回错误
        guard rawText.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: l10n.tool(
                    "tool.error.structured_health_card.empty_raw_text",
                    fallback: "缺少原始文本（摘要内容）。"
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }
        
        // 校验：缺少会话ID 或 助手消息客户端ID，返回内部错误
        guard let threadID = context.threadID, let assistantID = context.assistantMessageClientID else {
            return ToolExecutionResult(
                toolName: SparkToolName.generateStructuredHealthCard,
                outputText: l10n.tool(
                    "tool.error.structured_health_card.no_message_binding",
                    fallback: "[系统] 内部错误：未绑定助手消息。"
                ),
                sensitive: false,
                shouldBypassModel: true
            )
        }
        
        // 确定最终使用的报告类型，未传参则默认使用 medical_case
        let effectiveReportType = reportType.isEmpty ? "medical_case" : reportType
        
        // 解析 OSS 文件ID（转为整型，可选）
        let ossFileId = invocation.arguments["oss_file_id"].flatMap { Int($0) }
        let boundMemberID = context.memberID
        
        // 依赖的协程管理器与文档抽取器
        let merge = structuredHealthCardMergeCoordinator
        let extractor = typedMedicalDocumentExtractor
        
        // 开启后台任务：执行结构化健康卡片抽取与合并（不阻塞当前方法返回）
        Task {
            do {
                // 1. 从聊天摘要文本中抽取结构化健康数据
                let output = try await extractor.extractFromChatDistilledText(
                    memberID: boundMemberID,
                    reportType: effectiveReportType,
                    rawText: rawText
                )
                
                // 2. 构建卡片数据增量更新 payload
                let delta = ChatStructuredHealthCardsPayloadBuilder.appendPayloads(
                    from: output,
                    memberID: boundMemberID,
                    ossFileId: ossFileId
                )
                
                // 3. 等待助手消息就绪后，合并并追加结构化卡片
                await merge.mergeAppendWhenAssistantMessageReady(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    delta: delta
                )
            } catch {
                // 抽取失败：打印警告日志，并生成失败状态的卡片占位数据
                logger.warning(
                    "generate_structured_health_card 抽取失败：\(error.localizedDescription)",
                    module: .aiConfig
                )
                
                let delta = ChatStructuredHealthCardsPayloadBuilder.extractionFailureBlob(
                    memberID: boundMemberID,
                    reportType: effectiveReportType,
                    ossFileId: ossFileId
                )
                
                // 合并失败占位信息到助手消息
                await merge.mergeAppendWhenAssistantMessageReady(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    delta: delta
                )
            }
        }
        
        // 同步返回：立即告诉模型“后台正在生成”，不等待异步任务完成
        return ToolExecutionResult(
            toolName: SparkToolName.generateStructuredHealthCard,
            outputText: hintTemplate,
            sensitive: false,
            shouldBypassModel: false
        )
    }

    /// 拍照/上传卡片工具：解析 card_type，异步将 captureMessageCard block 合并回助手消息。
    private func runShowCustomMessageCard(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let cardType = (invocation.arguments["card_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = cardType.isEmpty ? "" : "（\(cardType)）"
        let outputText = "已展示上传/拍照卡片入口\(hint)，请继续引导用户上传材料。"

        guard let type = ChatCaptureCardType(rawValue: cardType),
              let threadID = context.threadID,
              let assistantID = context.assistantMessageClientID else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: outputText,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let payload = ChatCaptureMessageCardPayload(cardType: type)
        let merge = structuredHealthCardMergeCoordinator
        Task {
            await merge.insertCaptureCardWhenAssistantMessageReady(
                threadID: threadID,
                assistantClientMessageID: assistantID,
                payload: payload
            )
        }

        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: outputText,
            sensitive: false,
            shouldBypassModel: true
        )
    }

    private func runAskUserQuestion(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let questions = parseQuestionItems(arguments: invocation.arguments)
        guard questions.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.askUserQuestion,
                outputText: "【系统】ask_user_question 参数无效：需提供 1-5 个问题，每个问题的 options 必须包含 2-5 个选项。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        guard let toolInteractionCoordinator else {
            return ToolExecutionResult(
                toolName: SparkToolName.askUserQuestion,
                outputText: "【系统】当前界面无法展示问题选择 sheet，请直接向用户提问。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let prompt = ToolQuestionPrompt(questions: questions)
        let answerResult = await toolInteractionCoordinator.requestQuestionAnswer(
            threadID: context.threadID,
            prompt: prompt
        )
        let answer: ToolQuestionAnswer
        switch answerResult {
        case .success(let value):
            answer = value
        case .cancelled, .conflict:
            return ToolExecutionResult(
                toolName: SparkToolName.askUserQuestion,
                outputText: "【系统】用户取消或未提交问题选择。请继续当前对话，必要时用自然语言重新询问。",
                sensitive: false,
                shouldBypassModel: true,
                isAwaitingUserInput: true
            )
        }

        let output = formatQuestionAnswerText(questions: questions, responses: answer.responses)
        return ToolExecutionResult(
            toolName: SparkToolName.askUserQuestion,
            outputText: output,
            sensitive: false,
            shouldBypassModel: true
        )
    }

    private func parseQuestionItems(arguments: [String: String]) -> [ToolQuestionItem] {
        if let raw = arguments["questions"],
           let data = raw.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return Array(array.prefix(5)).enumerated().compactMap { index, object in
                let question = (object["question"] as? String ?? object["title"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rawOptions = object["options"] as? [String] ?? []
                let selectionMode = ChatQuestionSelectionMode(
                    rawValue: (object["selection_mode"] as? String ?? "single").lowercased()
                ) ?? .single
                let allowsOther = object["allows_other"] as? Bool ?? false
                return makeQuestionItem(
                    index: index,
                    question: question,
                    rawOptions: rawOptions,
                    selectionMode: selectionMode,
                    allowsOther: allowsOther
                )
            }
        }

        let question = (arguments["question"] ?? arguments["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let selectionMode = ChatQuestionSelectionMode(
            rawValue: (arguments["selection_mode"] ?? "single")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ) ?? .single
        return makeQuestionItem(
            index: 0,
            question: question,
            rawOptions: parseStringList(arguments["options"]),
            selectionMode: selectionMode,
            allowsOther: parseBool(arguments["allows_other"], defaultValue: false)
        ).map { [$0] } ?? []
    }

    private func makeQuestionItem(
        index: Int,
        question: String,
        rawOptions: [String],
        selectionMode: ChatQuestionSelectionMode,
        allowsOther: Bool
    ) -> ToolQuestionItem? {
        guard question.isEmpty == false, (2...5).contains(rawOptions.count) else { return nil }
        let questionID = "q\(index + 1)"
        let options = Array(rawOptions.prefix(5)).enumerated().map { optionIndex, text in
            ChatQuestionOption(id: "\(questionID)_option_\(optionIndex + 1)", text: text)
        }
        return ToolQuestionItem(
            id: questionID,
            question: question,
            options: options,
            allowsOther: allowsOther,
            selectionMode: selectionMode
        )
    }

    private func formatQuestionAnswerText(
        questions: [ToolQuestionItem],
        responses: [ToolQuestionResponse]
    ) -> String {
        var lines = [td("tool.result.ask_user_question.submitted")]
        for (index, question) in questions.enumerated() {
            let response = responses.first { $0.questionID == question.id }
            let selectedIDs = Set(response?.selectedOptionIDs ?? [])
            let selectedTexts = question.options
                .filter { selectedIDs.contains($0.id) }
                .map(\.text)
            let otherText = response?.otherText?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            lines.append(toolFormat("tool.result.ask_user_question.item", index + 1, question.question))
            if selectedTexts.isEmpty {
                lines.append(td("tool.result.ask_user_question.no_fixed_selection"))
            } else {
                lines.append(toolFormat(
                    "tool.result.ask_user_question.selected",
                    selectedTexts.joined(separator: td("tool.result.separator.list"))
                ))
            }
            if let otherText, otherText.isEmpty == false {
                lines.append(toolFormat("tool.result.ask_user_question.other", otherText))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 任务查询工具：按成员维度返回主任务与子任务信息，供后续任务生成去重。
    private func runQueryTasksByMember(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let memberID: Int
        if let resolved = await resolveTargetMemberID(invocation: invocation, context: context) {
            memberID = resolved
        } else if let selected = await awaitMemberSelection(
            invocation: invocation,
            context: context,
            reason: "query_tasks_by_member"
        ) {
            memberID = selected
        } else {
            return memberSelectionTimeoutResult(toolName: SparkToolName.queryTasksByMember.rawValue)
        }
        let includeCompleted = parseBool(invocation.arguments["include_completed"], defaultValue: true)
        let limit = max(1, min(Int(invocation.arguments["limit"] ?? "") ?? 50, 200))

        do {
            var tasks = try await taskService.fetchTasks(memberID: memberID, since: nil)
            if includeCompleted == false {
                tasks.removeAll { $0.status != .pending }
            }
            tasks = Array(tasks.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
            let output = formatTaskQueryText(memberID: memberID, tasks: tasks, queriedAt: Date())
            return ToolExecutionResult(
                toolName: SparkToolName.queryTasksByMember,
                outputText: output,
                sensitive: true,
                shouldBypassModel: true,
                resolvedMemberID: memberID
            )
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.queryTasksByMember,
                outputText: #"{"ok":false,"error":"task_query_failed"}"#,
                sensitive: false,
                shouldBypassModel: true,
                resolvedMemberID: memberID
            )
        }
    }

    private func formatTaskQueryText(memberID: Int, tasks: [HealthTask], queriedAt: Date) -> String {
        var lines = [
            toolFormat("tool.result.query_tasks_by_member.header", memberID),
            toolFormat("tool.result.query_tasks_by_member.queried_at", iso8601(queriedAt)),
            toolFormat("tool.result.query_tasks_by_member.total", tasks.count)
        ]
        guard tasks.isEmpty == false else {
            lines.append(td("tool.result.query_tasks_by_member.empty"))
            return lines.joined(separator: "\n")
        }

        lines.append(td("tool.result.query_tasks_by_member.list_title"))
        for (index, task) in tasks.enumerated() {
            lines.append(toolFormat("tool.result.query_tasks_by_member.task_item", index + 1, task.title))
            lines.append(toolFormat(
                "tool.result.query_tasks_by_member.task_meta",
                taskTypeText(task.type),
                taskStatusText(task.status),
                taskRepeatText(task.repeatType),
                taskPriorityText(task.priority)
            ))
            if let startTime = task.startTime {
                lines.append(toolFormat("tool.result.query_tasks_by_member.start_time", iso8601(startTime)))
            }
            if let dueTime = task.dueTime {
                lines.append(toolFormat("tool.result.query_tasks_by_member.due_time", iso8601(dueTime)))
            }
            let description = compactText(task.description)
            if description.isEmpty == false {
                lines.append(toolFormat("tool.result.query_tasks_by_member.description", description))
            }
            lines.append(toolFormat("tool.result.query_tasks_by_member.updated_at", iso8601(task.updatedAt)))
        }
        return lines.joined(separator: "\n")
    }

    /// 任务生成工具：先查询任务，再执行抽取与相似度判断；成功时在消息内异步合并任务卡 block，向模型只返回简短可读说明。
    private func runGenerateTask(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let memberID = await resolveTargetMemberID(invocation: invocation, context: context)
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
        if let memberID {
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
        } else {
            existingTasks = []
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
                "member_source": invocation.arguments["member_id"] == nil ? "thread_member_binding" : "explicit_member"
            ],
            ignoredReason: "",
            confirmedTask: nil,
            createdAt: iso8601(now),
            updatedAt: iso8601(now)
        )
        let taskCards = taskCardsFromToolCardPayload([card]) ?? []
        let titleLine = makeTaskTitle(extracted: extracted, type: taskType)
        let userFacing = "已根据描述生成 1 条待确认任务「\(titleLine)」。请在消息内任务卡片中确认或忽略。"
        if taskCards.isEmpty == false,
           let threadID = context.threadID,
           let assistantID = context.assistantMessageClientID {
            let merge = structuredHealthCardMergeCoordinator
            let normalizedToolCallID = context.pendingToolCallID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                await merge.insertTaskCardsWhenAssistantMessageReady(
                    threadID: threadID,
                    assistantClientMessageID: assistantID,
                    taskCards: taskCards,
                    anchorToolCallID: (normalizedToolCallID?.isEmpty == false ? normalizedToolCallID : nil),
                    )
            }
        }
        return ToolExecutionResult(
            toolName: SparkToolName.generateTask,
            outputText: userFacing,
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

    private func taskTypeText(_ type: HealthTask.TaskType) -> String {
        switch type {
        case .medical: return td("tool.result.task.type.medical")
        case .exercise: return td("tool.result.task.type.exercise")
        case .diet: return td("tool.result.task.type.diet")
        }
    }

    private func taskStatusText(_ status: HealthTask.TaskStatus) -> String {
        switch status {
        case .pending: return td("tool.result.task.status.pending")
        case .completed: return td("tool.result.task.status.completed")
        case .canceled: return td("tool.result.task.status.canceled")
        }
    }

    private func taskRepeatText(_ repeatType: HealthTask.RepeatType) -> String {
        switch repeatType {
        case .none: return td("tool.result.task.repeat.none")
        case .daily: return td("tool.result.task.repeat.daily")
        case .weekly: return td("tool.result.task.repeat.weekly")
        }
    }

    private func taskPriorityText(_ priority: HealthTask.Priority) -> String {
        switch priority {
        case .high: return td("tool.result.task.priority.high")
        case .medium: return td("tool.result.task.priority.medium")
        case .low: return td("tool.result.task.priority.low")
        }
    }

    private func compactText(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: td("tool.result.separator.sentence"))
    }

    private func buildTaskPayloadStrings(
        memberID: Int?,
        type: HealthTask.TaskType,
        extracted: TaskIntentExtraction,
        startAt: Date,
        dueAt: Date?,
        repeatType: HealthTask.RepeatType,
        priority: HealthTask.Priority
    ) -> [String: String] {
        var base: [String: Any] = [
            "creator_id": "current_user",
            "type": type.rawValue,
            "status": HealthTask.TaskStatus.pending.rawValue,
            "repeat_type": repeatType.rawValue,
            "priority": priority.rawValue,
            "source": HealthTask.Source.ai.rawValue,
            "start_time": iso8601(startAt),
            "due_time": dueAt.map(iso8601) ?? ""
        ]
        if let memberID {
            base["member_id"] = memberID
        }
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

    /// 解析任务归属成员：优先显式 member_id，其次当前会话绑定成员；未绑定时不隐式结合任何成员。
    private func resolveTargetMemberID(invocation: ToolInvocation, context: ToolExecutionContext) async -> Int? {
        if let value = invocation.arguments["member_id"], let explicit = Int(value) {
            return explicit
        }
        if let current = context.memberID {
            return current
        }
        if let threadID = context.threadID,
           let thread = await chatRepository.loadThread(id: threadID),
           let threadMemberID = thread.memberID,
           threadMemberID > 0 {
            return threadMemberID
        }
        return nil
    }

    private func awaitMemberSelection(
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        reason: String
    ) async -> Int? {
        guard let toolInteractionCoordinator else { return nil }
        var arguments = invocation.arguments
        if let memberID = context.memberID {
            arguments["member_id"] = String(memberID)
        }
        let prompt = ToolMemberSelectionPrompt(
            id: UUID(),
            toolName: invocation.name,
            reason: reason,
            arguments: arguments
        )
        switch await toolInteractionCoordinator.requestMemberSelection(threadID: context.threadID, prompt: prompt) {
        case .success(let memberID):
            return memberID
        case .cancelled, .conflict:
            return nil
        }
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

    /// 在助手消息落库后合并富 UI blocks；所有内容由调用处直接构建为 `ChatMessageBlock`。
    private func returnWithScheduledRichMerge(
        context: ToolExecutionContext,
        result: ToolExecutionResult,
        richBlocks: [ChatMessageBlock]
    ) -> ToolExecutionResult {
        guard richBlocks.isEmpty == false,
              let threadID = context.threadID,
              let assistantID = context.assistantMessageClientID
        else {
            return result
        }
        let merge = structuredHealthCardMergeCoordinator
        Task {
            await merge.mergeAppendRichPresentationWhenAssistantMessageReady(
                threadID: threadID,
                assistantClientMessageID: assistantID,
                blocks: richBlocks
            )
        }
        return result
    }

    /// 从 `ToolInvocation.arguments` 构建地图/日历/HTML 等富 UI blocks。
    private func makeExternalConnectorRichBlocks(
        invocation: ToolInvocation,
        toolOutputForWebPreview: String,
        toolCallID: String?
    ) -> [ChatMessageBlock] {
        let a = invocation.arguments
        var blocks: [ChatMessageBlock] = []
        let l10n = AIPromptL10n(locale: .current)
        let locDefault = l10n.tool("tool.ui.rich.location.default_name", fallback: "Location")
        let eventDefault = l10n.tool("tool.ui.rich.event.default_title", fallback: "Event")

        if let tool = SparkToolName(rawValue: invocation.name) {
            switch tool {
            case .queryLocation, .getCurrentLocation, .searchNearbyLocations, .getRoute:
                if let lat = Double(a["latitude"] ?? ""),
                   let lon = Double(a["longitude"] ?? "") {
                    let loc = [
                        ChatMapLocationPayload(
                            name: a["keyword"] ?? a["query"] ?? locDefault,
                            latitude: lat,
                            longitude: lon
                        )
                    ]
                    blocks.append(
                        ChatMessageBlock(
                            anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                            kind: .mapRoute,
                            toolCallID: toolCallID,
                            locations: loc,
                            routes: []
                        )
                    )
                }
                if let sLat = Double(a["start.latitude"] ?? ""),
                   let sLng = Double(a["start.longitude"] ?? ""),
                   let eLat = Double(a["end.latitude"] ?? ""),
                   let eLng = Double(a["end.longitude"] ?? "") {
                    let loc = [
                        ChatMapLocationPayload(name: "Start", latitude: sLat, longitude: sLng),
                        ChatMapLocationPayload(name: "End", latitude: eLat, longitude: eLng)
                    ]
                    let routes = [ChatRoutePayload(
                        summary: "Route",
                        distance: a["distance"],
                        duration: a["duration"],
                        mode: a["mode"]
                    )]
                    blocks.append(
                        ChatMessageBlock(
                            anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                            kind: .mapRoute,
                            toolCallID: toolCallID,
                            locations: loc,
                            routes: routes
                        )
                    )
                }
            case .searchCalendarAndReminders, .writeSystemEvent:
                let events = [ChatEventPayload(
                    type: a["event_type"] ?? a["type"] ?? "calendar",
                    title: a["title"] ?? a["keyword"] ?? eventDefault,
                    dateText: a["start_date"] ?? a["due_date"] ?? a["end_date"],
                    location: a["location"],
                    notes: a["notes"]
                )]
                blocks.append(
                    ChatMessageBlock(
                        anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                        kind: .events,
                        toolCallID: toolCallID,
                        events: events
                    )
                )
            case .readWebPage:
                if toolOutputForWebPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    blocks.append(
                        ChatMessageBlock(
                            anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                            kind: .html,
                            text: toolOutputForWebPreview,
                            toolCallID: toolCallID
                        )
                    )
                }
            default:
                break
            }
        }

        return blocks
    }

    /// 将工具内 `TaskToolCardPayload` 与消息内 `TaskCard` 对齐（与 `block(from: .taskCards)` 解码路径一致）。
    private func taskCardsFromToolCardPayload(_ cards: [TaskToolCardPayload]) -> [TaskCard]? {
        guard cards.isEmpty == false,
              let data = try? JSONEncoder().encode(cards),
              let raw = String(data: data, encoding: .utf8)?.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let out = try? decoder.decode([TaskCard].self, from: raw), out.isEmpty == false else { return nil }
        return out
    }

    /// 联网/网页读取优先走本地搜索网关；地图/天气/日历等外部工具暂按 `toolKeys` 返回路由说明。
    private func runExternalConnectorTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        if invocation.name == SparkToolName.searchOnline.rawValue || invocation.name == SparkToolName.searchArxivPapers.rawValue {
            return await runWebSearchTool(invocation: invocation, context: context)
        }

        if invocation.name == SparkToolName.readWebPage.rawValue || invocation.name == SparkToolName.extractRemoteFileContent.rawValue {
            return await runReadWebPageTool(invocation: invocation, context: context)
        }

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
        let rich = makeExternalConnectorRichBlocks(
            invocation: invocation,
            toolOutputForWebPreview: output,
            toolCallID: normalizedToolCallID(from: context)
        )
        return returnWithScheduledRichMerge(
            context: context,
            result: ToolExecutionResult(
                toolName: invocation.name,
                outputText: output,
                sensitive: false,
                shouldBypassModel: true
            ),
            richBlocks: rich
        )
    }

    private func runWebSearchTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["keyword"] ?? invocation.arguments["content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: SearchRuntimeError.emptyQuery.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let config = try await aiConfigCenter.effectiveSearchConfig()
            let primary = try await webSearchGateway.search(query: query, config: config)
            let combined = try await mergedBilingualSearchIfNeeded(primary: primary, query: query, config: config)
            let combinedMarkdown = combined.markdown
            let rich = [
                ChatMessageBlock(
                    anchor: normalizedToolCallID(from: context).map(ChatBlockAnchor.toolCall),
                    kind: .html,
                    text: combinedMarkdown,
                    toolCallID: normalizedToolCallID(from: context)
                )
            ]
            return returnWithScheduledRichMerge(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: combinedMarkdown,
                    sensitive: false,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    private func mergedBilingualSearchIfNeeded(
        primary: WebSearchResponse,
        query: String,
        config: SearchRuntimeConfig
    ) async throws -> WebSearchResponse {
        guard config.bilingualSearch else { return primary }
        let secondaryQuery: String
        do {
            secondaryQuery = try await translateSearchQueryForBilingualSearch(query)
        } catch {
            logger.warning("双语搜索翻译失败，使用原始搜索结果：\(error.localizedDescription)", module: .aiConfig)
            return primary
        }
        guard secondaryQuery.isEmpty == false, secondaryQuery.caseInsensitiveCompare(query) != .orderedSame else {
            return primary
        }
        let secondary = try await webSearchGateway.search(query: secondaryQuery, config: config)
        var seen = Set<String>()
        let mergedItems = (primary.items + secondary.items).filter { item in
            let key = normalizedSearchResultKey(item)
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
        return WebSearchResponse(
            providerName: primary.providerName,
            query: "\(primary.query) / \(secondary.query)",
            items: Array(mergedItems.prefix(max(config.searchCount, config.searchCount * 2))),
            totalEstimatedMatches: primary.totalEstimatedMatches ?? secondary.totalEstimatedMatches,
            revision: primary.revision
        )
    }

    private func translateSearchQueryForBilingualSearch(_ query: String) async throws -> String {
        let prompt = """
        请直接翻译以下搜索查询，保留原意并适合用于搜索引擎。
        如果输入是中文，翻译为英文；如果输入是其他语言，翻译为中文。
        只输出翻译后的查询，不要解释，不要加引号。

        \(query)
        """
        let stream = try await runtimeService.generateTextStream(
            request: AIRuntimeTextRequest(
                scenario: .optimizationText,
                messages: [
                    AIRuntimeMessage(
                        role: .system,
                        content: "You translate search queries for bilingual web search. Chinese queries must become English; non-Chinese queries must become Chinese. Return only the translated query."
                    ),
                    AIRuntimeMessage(role: .user, content: prompt)
                ],
                tools: [],
                toolChoice: .none,
                reasoning: .disabled,
                temperature: 0.2,
                maxTokens: 120
            )
        )
        return try await collectStreamText(from: stream)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`"))
    }

    private func normalizedSearchResultKey(_ item: WebSearchResultItem) -> String {
        let raw = item.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.title
            : item.url
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func runReadWebPageTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let url = (invocation.arguments["url"] ?? invocation.arguments["link"] ?? invocation.arguments["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.isEmpty == false else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "网页读取失败：url 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let text = try await webSearchGateway.readWebPage(urlString: url)
            let output = "网页读取结果\nURL: \(url)\n\n\(text)"
            let rich = [
                ChatMessageBlock(
                    anchor: normalizedToolCallID(from: context).map(ChatBlockAnchor.toolCall),
                    kind: .html,
                    text: output,
                    toolCallID: normalizedToolCallID(from: context)
                )
            ]
            return returnWithScheduledRichMerge(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: output,
                    sensitive: false,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    /// 将工具名映射到配置里的 `toolClass`（weather/map/calendar/code/tool），再取可用 `requestURL`。
    private func resolveEndpoint(for toolName: String, toolKeys: [ToolKeys]) -> String? {
        let toolClass: String
        guard let tool = SparkToolName(rawValue: toolName) else {
            toolClass = "tool"
            return toolKeys.first(where: { $0.toolClass == toolClass && $0.isUsing })?.requestURL
                ?? toolKeys.first(where: { $0.toolClass == toolClass })?.requestURL
        }

        switch tool {
        case .queryWeather:
            toolClass = "weather"
        case .queryLocation,
             .getCurrentLocation,
             .searchNearbyLocations,
             .getRoute:
            toolClass = "map"
        case .searchCalendarAndReminders,
             .writeSystemEvent:
            toolClass = "calendar"
        case .searchArxivPapers:
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

    private func normalizedToolCallID(from context: ToolExecutionContext) -> String? {
        let trimmed = context.pendingToolCallID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
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

private struct ToolQuestionAnswerPayload: Encodable {
    let responses: [Response]

    init(questions: [ToolQuestionItem], responses: [ToolQuestionResponse]) {
        self.responses = questions.map { question in
            let response = responses.first(where: { $0.questionID == question.id })
            let selectedIDs = Set(response?.selectedOptionIDs ?? [])
            return Response(
                questionID: question.id,
                question: question.question,
                selectionMode: question.selectionMode.rawValue,
                selectedOptions: question.options.filter { selectedIDs.contains($0.id) },
                otherText: response?.otherText
            )
        }
    }

    struct Response: Encodable {
        let questionID: String
        let question: String
        let selectionMode: String
        let selectedOptions: [ChatQuestionOption]
        let otherText: String?

        enum CodingKeys: String, CodingKey {
            case questionID = "question_id"
            case question
            case selectionMode = "selection_mode"
            case selectedOptions = "selected_options"
            case otherText = "other_text"
        }
    }
}

private struct TaskNoCreateToolPayload: Encodable {
    let ok: Bool
    let action: String
    let reason: String
    let queriedFirst: Bool
    let memberID: Int?
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

private struct TaskToolCardPayload: Encodable {
    let id: Int
    let member: Int?
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
