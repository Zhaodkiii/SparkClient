import Foundation

// ToolHub extension: OpenAI-compatible tool schema definitions and localization helpers.

extension ToolHub {
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
                "timeRange": AIRuntimeToolProperty(type: "string", description: td("tool.param.weather_time_range")),
                "locationName": AIRuntimeToolProperty(type: "string", description: td("tool.param.place_keyword"))
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
        case .showMedicalRiskNotice:
            return [
                "risk_level": AIRuntimeToolProperty(
                    type: "string",
                    description: td("tool.param.medical_risk_level"),
                    enumValues: ["low", "medium", "high", "emergency"]
                ),
                "title": AIRuntimeToolProperty(type: "string", description: td("tool.param.medical_risk_title")),
                "message": AIRuntimeToolProperty(type: "string", description: td("tool.param.medical_risk_message")),
                "recommended_action": AIRuntimeToolProperty(type: "string", description: td("tool.param.medical_risk_recommended_action")),
                "related_reason": AIRuntimeToolProperty(type: "string", description: td("tool.param.medical_risk_related_reason"))
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
        case .showMedicalRiskNotice:
            return ["risk_level", "message"]
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
}
