import SwiftUI

private enum AIToolSettingsSource: String {
    case deepTutorChat
    case chat

    var title: String {
        switch self {
        case .deepTutorChat: "DeepTutorChat"
        case .chat: "Chat"
        }
    }
}

private enum AIToolAvailability: String {
    case available
    case requiresSearchSettings
    case requiresWeatherSettings
    case requiresPermission
    case planned

    var title: String {
        switch self {
        case .available:
            L10n.text("ai_settings.ai_tools.availability.available", fallback: "Available")
        case .requiresSearchSettings:
            L10n.text("ai_settings.ai_tools.availability.search", fallback: "Requires Search")
        case .requiresWeatherSettings:
            L10n.text("ai_settings.ai_tools.availability.weather", fallback: "Requires Weather")
        case .requiresPermission:
            L10n.text("ai_settings.ai_tools.availability.permission", fallback: "Requires Permission")
        case .planned:
            L10n.text("ai_settings.ai_tools.availability.planned", fallback: "Planned")
        }
    }

    var color: Color {
        switch self {
        case .available: .green
        case .requiresSearchSettings, .requiresWeatherSettings: .blue
        case .requiresPermission: .orange
        case .planned: .secondary
        }
    }
}

private enum AIToolMountMode: String {
    case automatic
    case conditional
    case userToggleable

    var title: String {
        switch self {
        case .automatic:
            L10n.text("ai_settings.ai_tools.mount.auto", fallback: "Auto")
        case .conditional:
            L10n.text("ai_settings.ai_tools.mount.conditional", fallback: "Conditional")
        case .userToggleable:
            L10n.text("ai_settings.ai_tools.mount.user_toggleable", fallback: "User Optional")
        }
    }
}

private enum AIToolRelatedDestination {
    case search
    case weather

    var title: String {
        switch self {
        case .search:
            L10n.text("ai_settings.ai_tools.related.search", fallback: "Search Settings")
        case .weather:
            L10n.text("ai_settings.ai_tools.related.weather", fallback: "Weather Settings")
        }
    }
}

private struct AIToolSettingsItem: Identifiable {
    let id: String
    let displayName: String
    let definition: AIRuntimeToolDefinition
    let source: AIToolSettingsSource
    let category: String
    let availability: AIToolAvailability
    let mountMode: AIToolMountMode
    let relatedDestination: AIToolRelatedDestination?
}

private struct AIToolSettingsGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let tools: [AIToolSettingsItem]
}

struct AIToolSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        Form {
            Section {
                VStack(alignment: .center, spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.top, 4)

                    Text(L10n.text("ai_settings.ai_tools.intro", fallback: "Search providers stay in Search Settings. This page shows which tools DeepTutorChat and Chat can expose to the model, and why a tool may require another setting or permission."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            currentStatusSection

            Section(L10n.text("ai_settings.ai_tools.section.tool_lists", fallback: "Tool Lists")) {
                NavigationLink {
                    AIToolListView(
                        title: "DeepTutorChat",
                        subtitle: L10n.text("ai_settings.ai_tools.section.deeptutor.subtitle", fallback: "Native DeepTutorChat tools and DeepTutor-main compatible names."),
                        tools: AIToolCatalog.deepTutorTools(),
                        viewModel: viewModel
                    )
                } label: {
                    toolListRow(
                        title: "DeepTutorChat",
                        subtitle: L10n.text("ai_settings.ai_tools.section.deeptutor.subtitle", fallback: "Native DeepTutorChat tools and DeepTutor-main compatible names."),
                        icon: "graduationcap.fill",
                        count: AIToolCatalog.deepTutorTools().count
                    )
                }

                NavigationLink {
                    AIToolListView(
                        title: "Chat",
                        subtitle: L10n.text("ai_settings.ai_tools.section.chat.subtitle", fallback: "ToolHub tools used by the standard Chat runtime."),
                        tools: AIToolCatalog.chatTools(),
                        groups: AIToolCatalog.chatToolGroups(),
                        viewModel: viewModel
                    )
                } label: {
                    toolListRow(
                        title: "Chat",
                        subtitle: L10n.text("ai_settings.ai_tools.section.chat.subtitle", fallback: "ToolHub tools used by the standard Chat runtime."),
                        icon: "message.fill",
                        count: AIToolCatalog.chatTools().count
                    )
                }
            }
        }
        .navigationTitle(L10n.text("ai_settings.ai_tools.nav_title", fallback: "AI Tools"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var currentStatusSection: some View {
        Section(L10n.text("ai_settings.ai_tools.section.status", fallback: "Related settings")) {
            NavigationLink {
                AISearchToolSettingsView(viewModel: viewModel)
                    .hidesMainTabBarWhenPushed()
            } label: {
                statusRow(
                    title: L10n.text("ai_settings.search.nav_title", fallback: "Web Search"),
                    subtitle: searchStatusText,
                    icon: "magnifyingglass",
                    color: searchStatusColor
                )
            }

            NavigationLink {
                AIWeatherToolSettingsView(viewModel: viewModel)
                    .hidesMainTabBarWhenPushed()
            } label: {
                statusRow(
                    title: L10n.text("ai_settings.weather.nav_title", fallback: "Weather Enquiry"),
                    subtitle: weatherStatusText,
                    icon: "cloud.sun.fill",
                    color: weatherStatusColor
                )
            }
        }
    }

    private func toolListRow(title: String, subtitle: String, icon: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchStatusText: String {
        guard viewModel.snapshot.searchToolPreferences.useSearch else {
            return L10n.text("ai_settings.ai_tools.status.search_disabled", fallback: "Web Search is off. Search tools will report that web search is disabled.")
        }
        guard let active = SearchRuntimeConfigResolver.activeWebSearchKey(from: viewModel.snapshot) else {
            return L10n.text("ai_settings.ai_tools.status.search_missing", fallback: "Web Search is on, but no active provider is configured.")
        }
        let name = active.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? active.company : active.name
        return L10n.format("ai_settings.ai_tools.status.search_active_format", name)
    }

    private var searchStatusColor: Color {
        if viewModel.snapshot.searchToolPreferences.useSearch,
           SearchRuntimeConfigResolver.activeWebSearchKey(from: viewModel.snapshot) != nil {
            return .green
        }
        return .orange
    }

    private var weatherStatusText: String {
        guard viewModel.snapshot.weatherToolPreferences.useWeather else {
            return L10n.text("ai_settings.ai_tools.status.weather_disabled", fallback: "Weather is off. Weather tools will not query providers.")
        }
        guard let active = WeatherRuntimeConfigResolver.activeWeatherKey(from: viewModel.snapshot) else {
            return L10n.text("ai_settings.ai_tools.status.weather_missing", fallback: "Weather is on, but no active provider is configured.")
        }
        let name = active.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? active.company : active.name
        return L10n.format("ai_settings.ai_tools.status.weather_active_format", name)
    }

    private var weatherStatusColor: Color {
        if viewModel.snapshot.weatherToolPreferences.useWeather,
           WeatherRuntimeConfigResolver.activeWeatherKey(from: viewModel.snapshot) != nil {
            return .green
        }
        return .orange
    }
}

private struct AIToolListView: View {
    let title: String
    let subtitle: String
    let tools: [AIToolSettingsItem]
    var groups: [AIToolSettingsGroup] = []
    @ObservedObject var viewModel: AISettingsViewModel
    @State private var expandedGroupIDs: Set<String> = AIToolCatalog.defaultExpandedChatGroupIDs

    var body: some View {
        List {
            Section {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if groups.isEmpty {
                Section(L10n.text("ai_settings.ai_tools.section.tools", fallback: "Tools")) {
                    ForEach(tools) { tool in
                        toolNavigationLink(tool)
                    }
                }
            } else {
                ForEach(groups) { group in
                    Section {
                        DisclosureGroup(isExpanded: binding(for: group.id)) {
                            ForEach(group.tools) { tool in
                                toolNavigationLink(tool)
                            }
                        } label: {
                            AIToolGroupHeader(group: group)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }

    private func binding(for groupID: String) -> Binding<Bool> {
        Binding {
            expandedGroupIDs.contains(groupID)
        } set: { isExpanded in
            if isExpanded {
                expandedGroupIDs.insert(groupID)
            } else {
                expandedGroupIDs.remove(groupID)
            }
        }
    }

    private func toolNavigationLink(_ tool: AIToolSettingsItem) -> some View {
        NavigationLink {
            AIToolDetailView(tool: tool, viewModel: viewModel)
        } label: {
            AIToolListRow(tool: tool)
        }
    }
}

private struct AIToolGroupHeader: View {
    let group: AIToolSettingsGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text("\(group.tools.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(group.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct AIToolListRow: View {
    let tool: AIToolSettingsItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tool.availability.color)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 5) {
                Text(tool.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(tool.definition.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(tool.definition.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    AIToolBadge(text: tool.availability.title, color: tool.availability.color)
                    AIToolBadge(text: tool.mountMode.title, color: .secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var iconName: String {
        switch tool.availability {
        case .requiresSearchSettings:
            return "magnifyingglass"
        case .requiresWeatherSettings:
            return "cloud.sun.fill"
        case .requiresPermission:
            return "lock.shield"
        case .planned:
            return "clock"
        case .available:
            break
        }

        switch tool.category.lowercased() {
        case let value where value.contains("health") || value.contains("健康"):
            return "heart.text.square"
        case let value where value.contains("member") || value.contains("成员"):
            return "person.2"
        case let value where value.contains("location") || value.contains("weather") || value.contains("位置") || value.contains("天气"):
            return "cloud.sun"
        case let value where value.contains("memory") || value.contains("conversation") || value.contains("记忆") || value.contains("对话"):
            return "archivebox"
        case let value where value.contains("knowledge") || value.contains("network") || value.contains("search") || value.contains("知识") || value.contains("网络"):
            return "magnifyingglass"
        case let value where value.contains("system") || value.contains("task") || value.contains("系统") || value.contains("任务"):
            return "checklist"
        default:
            return "wrench.and.screwdriver"
        }
    }
}

private struct AIToolDetailView: View {
    let tool: AIToolSettingsItem
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        AIToolBadge(text: tool.source.title, color: .blue)
                        AIToolBadge(text: tool.category, color: .secondary)
                        AIToolBadge(text: tool.availability.title, color: tool.availability.color)
                        AIToolBadge(text: tool.mountMode.title, color: .secondary)
                    }
                    Text(tool.definition.name)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }

            Section(L10n.text("ai_settings.ai_tools.detail.prompt", fallback: "Prompt")) {
                Text(tool.definition.summary)
                    .font(.body)
                    .textSelection(.enabled)
            }

            Section(L10n.text("ai_settings.ai_tools.detail.required", fallback: "Required Parameters")) {
                if tool.definition.required.isEmpty {
                    Text(L10n.text("ai_settings.ai_tools.detail.none", fallback: "None"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tool.definition.required, id: \.self) { name in
                        Text(name)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section(L10n.text("ai_settings.ai_tools.detail.parameters", fallback: "Parameters")) {
                if tool.definition.properties.isEmpty {
                    Text(L10n.text("ai_settings.ai_tools.detail.no_parameters", fallback: "This tool does not take parameters."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tool.definition.properties.keys.sorted(), id: \.self) { name in
                        if let property = tool.definition.properties[name] {
                            AIToolPropertyView(
                                name: name,
                                property: property,
                                required: tool.definition.required.contains(name),
                                depth: 0
                            )
                        }
                    }
                }
            }

            if let destination = tool.relatedDestination {
                Section(L10n.text("ai_settings.ai_tools.detail.related_settings", fallback: "Related Settings")) {
                    NavigationLink {
                        relatedDestinationView(destination)
                    } label: {
                        Label(destination.title, systemImage: "arrow.up.right.circle")
                    }
                }
            }
        }
        .navigationTitle(tool.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func relatedDestinationView(_ destination: AIToolRelatedDestination) -> some View {
        switch destination {
        case .search:
            AISearchToolSettingsView(viewModel: viewModel)
                .hidesMainTabBarWhenPushed()
        case .weather:
            AIWeatherToolSettingsView(viewModel: viewModel)
                .hidesMainTabBarWhenPushed()
        }
    }
}

private struct AIToolPropertyView: View {
    let name: String
    let property: AIRuntimeToolProperty
    let required: Bool
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(.body.monospaced().weight(.semibold))
                Text(property.type)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if required {
                    AIToolBadge(
                        text: L10n.text("ai_settings.ai_tools.detail.required_badge", fallback: "Required"),
                        color: .orange
                    )
                }
            }
            if let format = property.format {
                Text("format: \(format)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(property.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let enumValues = property.enumValues, enumValues.isEmpty == false {
                Text("enum: \(enumValues.joined(separator: " / "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let objectProperties = property.objectProperties, objectProperties.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(objectProperties.keys.sorted(), id: \.self) { childName in
                        if let child = objectProperties[childName] {
                            AIToolPropertyView(
                                name: childName,
                                property: child,
                                required: property.objectRequired?.contains(childName) == true,
                                depth: depth + 1
                            )
                        }
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                }
            }
            if let arrayItems = property.arrayItems {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("ai_settings.ai_tools.detail.array_items", fallback: "Array items"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    AIToolPropertyView(
                        name: "item",
                        property: arrayItems,
                        required: false,
                        depth: depth + 1
                    )
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                }
            }
        }
        .padding(.vertical, depth == 0 ? 4 : 0)
    }
}

private struct AIToolBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private enum AIToolCatalog {
    static let defaultExpandedChatGroupIDs: Set<String> = Set([
        "health_data",
        "member_management",
        "location_weather",
        "memory_conversation",
        "knowledge_network",
        "system_tasks"
    ])

    static func deepTutorTools() -> [AIToolSettingsItem] {
        nativeDeepTutorTools() + deepTutorCompatibilityTools()
    }

    static func chatTools() -> [AIToolSettingsItem] {
        SparkToolName.allCases.map { tool in
            AIToolSettingsItem(
                id: "chat.\(tool.rawValue)",
                displayName: displayName(for: tool.rawValue),
                definition: ChatToolSchemaCatalog.definition(for: tool),
                source: .chat,
                category: chatCategory(for: tool),
                availability: chatAvailability(for: tool),
                mountMode: chatMountMode(for: tool),
                relatedDestination: relatedDestination(for: tool)
            )
        }
    }

    static func chatToolGroups() -> [AIToolSettingsGroup] {
        let tools = chatTools()

        func matching(_ toolNames: [SparkToolName]) -> [AIToolSettingsItem] {
            let ids = Set(toolNames.map { "chat.\($0.rawValue)" })
            return tools.filter { ids.contains($0.id) }
        }

        return [
            AIToolSettingsGroup(
                id: "health_data",
                title: chatGroupTitle("health_data", fallback: "Health Data"),
                subtitle: chatGroupSubtitle("health_data", fallback: "Gets body, activity, sleep, nutrition, energy, and other health data."),
                tools: matching([
                    .fetchStepDetails,
                    .fetchEnergyDetails,
                    .fetchNutritionDetails,
                    .makeNutritionData,
                    .fetchSleepDetails,
                    .fetchWorkoutDetails,
                    .generateStructuredHealthCard,
                    .listMemberHealthSources,
                    .getHealthResourceReference,
                    .getHealthResourceContext
                ])
            ),
            AIToolSettingsGroup(
                id: "member_management",
                title: chatGroupTitle("member_management", fallback: "Member Management"),
                subtitle: chatGroupSubtitle("member_management", fallback: "Switches, queries, and loads family member information."),
                tools: matching([
                    .getCurrentMember,
                    .requestMemberSelection,
                    .switchMember,
                    .findMember,
                    .queryMemberProfile
                ])
            ),
            AIToolSettingsGroup(
                id: "location_weather",
                title: chatGroupTitle("location_weather", fallback: "Location & Weather"),
                subtitle: chatGroupSubtitle("location_weather", fallback: "Handles location, routes, nearby places, and weather queries."),
                tools: matching([
                    .queryLocation,
                    .getCurrentLocation,
                    .searchNearbyLocations,
                    .getRoute,
                    .queryWeather
                ])
            ),
            AIToolSettingsGroup(
                id: "memory_conversation",
                title: chatGroupTitle("memory_conversation", fallback: "Memory & Conversation"),
                subtitle: chatGroupSubtitle("memory_conversation", fallback: "Stores, reads, and updates AI memory, and generates conversation titles."),
                tools: matching([
                    .saveMemory,
                    .retrieveMemory,
                    .updateMemory,
                    .generateChatTitle
                ])
            ),
            AIToolSettingsGroup(
                id: "knowledge_network",
                title: chatGroupTitle("knowledge_network", fallback: "Knowledge & Network"),
                subtitle: chatGroupSubtitle("knowledge_network", fallback: "Uses web search, documents, web pages, papers, and knowledge bases."),
                tools: matching([
                    .searchKnowledgeBag,
                    .createKnowledgeDocument,
                    .searchOnline,
                    .readWebPage,
                    .searchArxivPapers,
                    .extractRemoteFileContent
                ])
            ),
            AIToolSettingsGroup(
                id: "system_tasks",
                title: chatGroupTitle("system_tasks", fallback: "System & Tasks"),
                subtitle: chatGroupSubtitle("system_tasks", fallback: "Handles system events, calendar reminders, canvas, tasks, and UI display."),
                tools: matching([
                    .searchCalendarAndReminders,
                    .writeSystemEvent,
                    .createCanvas,
                    .editCanvas,
                    .queryTasksByMember,
                    .generateTask,
                    .showCustomMessageCard,
                    .askUserQuestion,
                    .showMedicalRiskNotice
                ])
            )
        ]
    }

    private static func nativeDeepTutorTools() -> [AIToolSettingsItem] {
        [
            deepTutorNative(
                name: "ask_user",
                category: "Interaction",
                mountMode: .automatic,
                summary: "Pause the conversation to ask the user 1-4 clarifying questions in one card. Use only when blocked on a decision that is genuinely the user's to make.",
                properties: [
                    "intro": prop("string", "Optional one-line lead-in shown above the questions."),
                    "questions": prop(
                        "array",
                        "1-4 questions to ask in one card. Bundle all clarifications into this single call.",
                        items: prop(
                            "object",
                            "Clarifying question",
                            objectProperties: [
                                "id": prop("string", "Stable question id."),
                                "header": prop("string", "Very short tab label, max 12 chars."),
                                "prompt": prop("string", "The complete question text."),
                                "options": prop(
                                    "array",
                                    "2-4 concise options when useful.",
                                    items: prop(
                                        "object",
                                        "Option",
                                        objectProperties: [
                                            "label": prop("string", "Concise option label."),
                                            "description": prop("string", "What this option means.")
                                        ],
                                        objectRequired: ["label"]
                                    )
                                ),
                                "multi_select": prop("boolean", "Whether multiple options may be selected."),
                                "allow_free_text": prop("boolean", "Whether free text is allowed."),
                                "placeholder": prop("string", "Free text placeholder.")
                            ],
                            objectRequired: ["prompt"]
                        )
                    )
                ],
                required: ["questions"]
            ),
            deepTutorNative(
                name: "get_current_member_binding",
                category: "Member",
                mountMode: .automatic,
                summary: "Check whether the current DeepTutorChat conversation is already bound to a family member."
            ),
            deepTutorNative(
                name: "request_member_selection",
                category: "Member",
                mountMode: .automatic,
                summary: "Pause the turn and ask the user to choose the family member this answer should use.",
                properties: [
                    "reason": prop("string", "Why a member is needed for this request."),
                    "required_context": prop("string", "The kind of member-specific context required."),
                    "allow_skip": prop("boolean", "Whether the user may continue without selecting a member.")
                ],
                required: ["reason"]
            ),
            deepTutorNative(
                name: "query_member_profile",
                category: "Health Records",
                mountMode: .automatic,
                summary: "Load the bound member's medical profile, health history, lifestyle, exam archive and risk summary before creating any personalized health-check plan.",
                properties: [
                    "member_id": prop("integer", "Optional explicit member id. Usually omit this and use the current bound member."),
                    "focus": prop("string", "Optional planning focus such as cancer screening, cardiovascular, thyroid, women's health, bone density, or budget.")
                ]
            ),
            deepTutorNative(
                name: "read_memory",
                category: "Memory",
                mountMode: .conditional,
                summary: "Read the user's persistent memory for personalization. Use for tone, depth, format, and explicit preferences; not on every turn."
            ),
            deepTutorNative(
                name: "write_memory",
                category: "Memory",
                mountMode: .automatic,
                summary: "Save an explicit user preference to long-term memory. Call only when the user clearly states a preference; never speculate.",
                properties: [
                    "op": prop("string", "`add` for a new preference, `edit` to revise an existing one.", enumValues: ["add", "edit"]),
                    "text": prop("string", "The preference, in the user's own words where possible. <= 240 chars."),
                    "target_id": prop("string", "Existing entry id. Required for edit."),
                    "reason": prop("string", "Optional one-line note.")
                ],
                required: ["op", "text"]
            ),
            deepTutorNative(
                name: "show_custom_message_card",
                category: "Cards",
                mountMode: .automatic,
                summary: "Insert a DeepTutorChat upload/capture card and pause the turn while the user chooses an attachment.",
                properties: [
                    "card_type": prop(
                        "string",
                        "Card type to show: report_photo for medical reports/PDFs, medicine_box_photo for medicine package photos, skin_photo for skin photos.",
                        enumValues: ["report_photo", "medicine_box_photo", "skin_photo"]
                    )
                ],
                required: ["card_type"]
            )
        ]
    }

    private static func deepTutorCompatibilityTools() -> [AIToolSettingsItem] {
        [
            deepTutorCompatibility(
                name: "web_search",
                category: "Search",
                availability: .requiresSearchSettings,
                summary: L10n.text("ai_settings.ai_tools.summary.deeptutor_web_search", fallback: "DeepTutor-main compatible web search name. SparkClient resolves it through Web Search settings and the active provider."),
                properties: ["query": prop("string", L10n.text("tool.param.search_query", fallback: "Search query"))],
                required: ["query"],
                relatedDestination: .search
            ),
            deepTutorCompatibility(
                name: "paper_search",
                category: "Search",
                availability: .requiresSearchSettings,
                summary: L10n.text("ai_settings.ai_tools.summary.deeptutor_paper_search", fallback: "Academic search name from DeepTutor-main. Availability depends on the SparkClient search runtime and paper-search executor."),
                properties: ["query": prop("string", L10n.text("tool.param.search_query", fallback: "Search query"))],
                required: ["query"],
                relatedDestination: .search
            ),
            deepTutorCompatibility(
                name: "imagegen",
                category: "Media",
                availability: .planned,
                summary: L10n.text("ai_settings.ai_tools.summary.planned_deeptutor", fallback: "Declared as a DeepTutor-main compatible tool name, but not yet wired as a native DeepTutorChat executor in this client.")
            ),
            deepTutorCompatibility(
                name: "videogen",
                category: "Media",
                availability: .planned,
                summary: L10n.text("ai_settings.ai_tools.summary.planned_deeptutor", fallback: "Declared as a DeepTutor-main compatible tool name, but not yet wired as a native DeepTutorChat executor in this client.")
            )
        ]
    }

    private static func deepTutorNative(
        name: String,
        category: String,
        mountMode: AIToolMountMode,
        summary: String,
        properties: [String: AIRuntimeToolProperty] = [:],
        required: [String] = []
    ) -> AIToolSettingsItem {
        AIToolSettingsItem(
            id: "deeptutor.\(name)",
            displayName: displayName(for: name),
            definition: AIRuntimeToolDefinition(
                name: name,
                summary: summary,
                properties: properties,
                required: required
            ),
            source: .deepTutorChat,
            category: category,
            availability: .available,
            mountMode: mountMode,
            relatedDestination: nil
        )
    }

    private static func deepTutorCompatibility(
        name: String,
        category: String,
        availability: AIToolAvailability,
        summary: String,
        properties: [String: AIRuntimeToolProperty] = [:],
        required: [String] = [],
        relatedDestination: AIToolRelatedDestination? = nil
    ) -> AIToolSettingsItem {
        AIToolSettingsItem(
            id: "deeptutor.\(name)",
            displayName: displayName(for: name),
            definition: AIRuntimeToolDefinition(
                name: name,
                summary: summary,
                properties: properties,
                required: required
            ),
            source: .deepTutorChat,
            category: category,
            availability: availability,
            mountMode: .userToggleable,
            relatedDestination: relatedDestination
        )
    }

    private static func prop(
        _ type: String,
        _ description: String,
        enumValues: [String]? = nil,
        format: String? = nil,
        objectProperties: [String: AIRuntimeToolProperty]? = nil,
        objectRequired: [String]? = nil,
        items: AIRuntimeToolProperty? = nil
    ) -> AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: type,
            description: description,
            enumValues: enumValues,
            format: format,
            objectProperties: objectProperties,
            objectRequired: objectRequired,
            arrayItems: items
        )
    }

    private static func displayName(for toolName: String) -> String {
        let localized = L10n.text("ai_settings.tools.\(toolName)", fallback: "")
        return localized.isEmpty ? toolName : localized
    }

    private static func chatAvailability(for tool: SparkToolName) -> AIToolAvailability {
        switch tool {
        case .searchOnline, .readWebPage, .searchArxivPapers, .extractRemoteFileContent:
            return .requiresSearchSettings
        case .queryWeather:
            return .requiresWeatherSettings
        case .fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails, .fetchSleepDetails, .fetchWorkoutDetails:
            return .requiresPermission
        default:
            return .available
        }
    }

    private static func chatMountMode(for tool: SparkToolName) -> AIToolMountMode {
        switch chatAvailability(for: tool) {
        case .requiresPermission, .requiresSearchSettings, .requiresWeatherSettings:
            return .conditional
        case .available:
            return .automatic
        case .planned:
            return .userToggleable
        }
    }

    private static func chatCategory(for tool: SparkToolName) -> String {
        switch tool {
        case .fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails, .makeNutritionData,
             .fetchSleepDetails, .fetchWorkoutDetails, .generateStructuredHealthCard,
             .listMemberHealthSources, .getHealthResourceReference, .getHealthResourceContext:
            return chatGroupTitle("health_data", fallback: "Health Data")
        case .getCurrentMember, .requestMemberSelection, .switchMember, .findMember, .queryMemberProfile:
            return chatGroupTitle("member_management", fallback: "Member Management")
        case .queryLocation, .getCurrentLocation, .searchNearbyLocations, .getRoute, .queryWeather:
            return chatGroupTitle("location_weather", fallback: "Location & Weather")
        case .saveMemory, .retrieveMemory, .updateMemory, .generateChatTitle:
            return chatGroupTitle("memory_conversation", fallback: "Memory & Conversation")
        case .searchKnowledgeBag, .createKnowledgeDocument,
             .searchOnline, .readWebPage, .searchArxivPapers, .extractRemoteFileContent:
            return chatGroupTitle("knowledge_network", fallback: "Knowledge & Network")
        case .searchCalendarAndReminders, .writeSystemEvent,
             .createCanvas, .editCanvas, .queryTasksByMember, .generateTask,
             .showCustomMessageCard, .askUserQuestion, .showMedicalRiskNotice:
            return chatGroupTitle("system_tasks", fallback: "System & Tasks")
        }
    }

    private static func chatGroupTitle(_ id: String, fallback: String) -> String {
        L10n.text("ai_settings.ai_tools.chat_group.\(id)", fallback: fallback)
    }

    private static func chatGroupSubtitle(_ id: String, fallback: String) -> String {
        L10n.text("ai_settings.ai_tools.chat_group.\(id).subtitle", fallback: fallback)
    }

    private static func relatedDestination(for tool: SparkToolName) -> AIToolRelatedDestination? {
        switch tool {
        case .searchOnline, .readWebPage, .searchArxivPapers, .extractRemoteFileContent:
            return .search
        case .queryWeather:
            return .weather
        default:
            return nil
        }
    }
}

private enum ChatToolSchemaCatalog {
    static func definition(for tool: SparkToolName) -> AIRuntimeToolDefinition {
        AIRuntimeToolDefinition(
            name: tool.rawValue,
            summary: td("tool.summary.\(tool.rawValue)"),
            properties: properties(for: tool),
            required: required(for: tool)
        )
    }

    private static func td(_ key: String) -> String {
        AIPromptL10n(locale: .current).tool(key)
    }

    private static func prop(
        _ type: String,
        _ descriptionKey: String,
        enumValues: [String]? = nil,
        format: String? = nil,
        objectProperties: [String: AIRuntimeToolProperty]? = nil,
        objectRequired: [String]? = nil,
        items: AIRuntimeToolProperty? = nil
    ) -> AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: type,
            description: td(descriptionKey),
            enumValues: enumValues,
            format: format,
            objectProperties: objectProperties,
            objectRequired: objectRequired,
            arrayItems: items
        )
    }

    private static func literalProp(
        _ type: String,
        _ description: String,
        enumValues: [String]? = nil,
        objectProperties: [String: AIRuntimeToolProperty]? = nil,
        objectRequired: [String]? = nil,
        items: AIRuntimeToolProperty? = nil
    ) -> AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: type,
            description: description,
            enumValues: enumValues,
            objectProperties: objectProperties,
            objectRequired: objectRequired,
            arrayItems: items
        )
    }

    private static var dateRangeProperties: [String: AIRuntimeToolProperty] {
        [
            "start_date": prop("string", "tool.date.start_yyyy_mm_dd", format: "date"),
            "end_date": prop("string", "tool.date.end_yyyy_mm_dd", format: "date")
        ]
    }

    private static var coordinateProperty: AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: "object",
            description: td("tool.coord.wgs84_description"),
            objectProperties: [
                "latitude": prop("number", "tool.coord.latitude_sentence"),
                "longitude": prop("number", "tool.coord.longitude_sentence")
            ],
            objectRequired: ["latitude", "longitude"]
        )
    }

    private static var healthResourceTypeProperty: AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: "string",
            description: td("tool.param.health_resource_type_enum"),
            enumValues: HealthResourceType.allCases.map(\.rawValue)
        )
    }

    private static var healthResourceTypesProperty: AIRuntimeToolProperty {
        AIRuntimeToolProperty(
            type: "array",
            description: td("tool.param.health_resource_types_filter"),
            arrayItems: healthResourceTypeProperty
        )
    }

    private static func properties(for tool: SparkToolName) -> [String: AIRuntimeToolProperty] {
        switch tool {
        case .fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails, .fetchSleepDetails:
            return dateRangeProperties
        case .makeNutritionData:
            return [
                "protein": prop("number", "tool.param.protein_g"),
                "carbohydrates": prop("number", "tool.param.carbohydrates_g"),
                "fat": prop("number", "tool.param.fat_g"),
                "energy": prop("number", "tool.param.energy_kcal")
            ]
        case .showMedicalRiskNotice:
            return [
                "risk_level": prop("string", "tool.param.medical_risk_level", enumValues: ["low", "medium", "high", "emergency"]),
                "title": prop("string", "tool.param.medical_risk_title"),
                "message": prop("string", "tool.param.medical_risk_message"),
                "recommended_action": prop("string", "tool.param.medical_risk_recommended_action"),
                "related_reason": prop("string", "tool.param.medical_risk_related_reason")
            ]
        case .fetchWorkoutDetails:
            var props = dateRangeProperties
            props["types"] = prop("array", "tool.param.activity_types_filter", items: prop("string", "tool.param.activity_type_item"))
            props["max_items"] = prop("integer", "tool.param.max_items")
            return props
        case .generateStructuredHealthCard:
            return [
                "report_type": prop("string", "tool.param.report_type_enum", enumValues: ["medication_plan", "medicine_box", "prescription", "exam_report", "medical_case"]),
                "raw_text": prop("string", "tool.param.raw_text_distilled"),
                "oss_file_id": prop("integer", "tool.param.oss_file_id_optional")
            ]
        case .listMemberHealthSources:
            var props = dateRangeProperties
            props["member_id"] = prop("integer", "tool.param.member_id_optional")
            props["resource_type"] = healthResourceTypeProperty
            props["resource_types"] = healthResourceTypesProperty
            props["keyword"] = prop("string", "tool.param.health_keyword")
            props["limit"] = prop("integer", "tool.param.health_sources_limit")
            return props
        case .getHealthResourceReference, .getHealthResourceContext:
            var props: [String: AIRuntimeToolProperty] = [
                "resource_type": healthResourceTypeProperty,
                "resource_id": prop("integer", "tool.param.health_resource_id"),
                "member_id": prop("integer", "tool.param.member_id_optional")
            ]
            if tool == .getHealthResourceContext {
                props["topic"] = prop("string", "tool.param.health_topic_focus")
                props["references"] = prop("string", "tool.param.health_references_json")
            }
            return props
        case .searchKnowledgeBag:
            return ["query": prop("string", "tool.param.query_keyword")]
        case .createKnowledgeDocument:
            return [
                "title": prop("string", "tool.param.doc_title"),
                "content": prop("string", "tool.param.doc_content_markdown")
            ]
        case .searchCalendarAndReminders:
            return [
                "keyword": prop("string", "tool.param.keyword_title_notes"),
                "start_date": prop("string", "tool.param.start_date_inclusive", format: "date"),
                "end_date": prop("string", "tool.param.end_date_inclusive", format: "date"),
                "location": prop("string", "tool.param.location_keyword"),
                "event_type": prop("string", "tool.param.calendar_or_reminder_enum", enumValues: ["calendar", "reminder"])
            ]
        case .writeSystemEvent:
            return [
                "type": prop("string", "tool.param.calendar_or_reminder_enum", enumValues: ["calendar", "reminder"]),
                "title": prop("string", "tool.param.title"),
                "start_date": prop("string", "tool.param.start_iso8601_tz", format: "date-time"),
                "end_date": prop("string", "tool.param.end_iso8601_tz", format: "date-time"),
                "due_date": prop("string", "tool.param.due_iso8601_tz", format: "date-time"),
                "location": prop("string", "tool.param.location_calendar_only"),
                "notes": prop("string", "tool.param.notes"),
                "priority": prop("integer", "tool.param.reminder_priority"),
                "reminder_minutes": prop("integer", "tool.param.reminder_minutes")
            ]
        case .queryLocation:
            return ["keyword": prop("string", "tool.param.place_keyword")]
        case .getCurrentLocation:
            return ["query": prop("string", "tool.param.query_fixed_local", enumValues: ["local"])]
        case .searchNearbyLocations:
            return [
                "coordinate": coordinateProperty,
                "keyword": prop("string", "tool.param.search_keyword_poi")
            ]
        case .getRoute:
            let point = AIRuntimeToolProperty(
                type: "object",
                description: td("tool.param.latlon_point_object"),
                objectProperties: [
                    "latitude": prop("number", "tool.param.latitude"),
                    "longitude": prop("number", "tool.param.longitude")
                ],
                objectRequired: ["latitude", "longitude"]
            )
            return [
                "start": point,
                "end": point,
                "mode": prop("string", "tool.param.transport_mode", enumValues: ["driving", "walking", "transit"])
            ]
        case .queryWeather:
            return [
                "latitude": prop("number", "tool.param.latitude"),
                "longitude": prop("number", "tool.param.longitude"),
                "timeRange": prop("string", "tool.param.weather_time_range"),
                "locationName": prop("string", "tool.param.place_keyword")
            ]
        case .saveMemory:
            return ["content": prop("string", "tool.param.memory_content")]
        case .retrieveMemory:
            return ["keyword": prop("string", "tool.param.memory_keywords")]
        case .updateMemory:
            return [
                "originalContent": prop("string", "tool.param.memory_original"),
                "updatedContent": prop("string", "tool.param.memory_updated")
            ]
        case .generateChatTitle, .getCurrentMember, .switchMember:
            return [:]
        case .showCustomMessageCard:
            return [
                "card_type": prop("string", "tool.param.attachment_types", enumValues: ["report_photo", "medicine_box_photo", "skin_photo"])
            ]
        case .requestMemberSelection:
            return ["reason": prop("string", "tool.param.member_selection_reason")]
        case .findMember:
            return [
                "name": prop("string", "tool.param.member_name_optional"),
                "relationship": prop("string", "tool.param.member_relationship_optional")
            ]
        case .queryMemberProfile:
            return [
                "query_type": prop("string", "tool.param.query_type_enum", enumValues: ["summary", "medications", "hospital_exams", "medical_records", "health_exams"]),
                "member_id": prop("string", "tool.param.member_id_optional"),
                "days": prop("integer", "tool.param.days_optional"),
                "limit": prop("integer", "tool.param.limit_optional")
            ]
        case .searchOnline, .searchArxivPapers:
            return ["query": prop("string", "tool.param.search_query")]
        case .readWebPage, .extractRemoteFileContent:
            return ["url": prop("string", "tool.param.url_full")]
        case .createCanvas:
            return [
                "title": prop("string", "tool.param.canvas_title"),
                "content": prop("string", "tool.param.canvas_body"),
                "type": prop("string", "tool.param.canvas_type_enum", enumValues: ["text", "python", "html"])
            ]
        case .editCanvas:
            return [
                "title": prop("string", "tool.param.canvas_title_edit"),
                "patterns": prop("array", "tool.param.patterns_array", items: prop("string", "tool.param.regex_item")),
                "replacements": prop("array", "tool.param.replacements_array", items: prop("string", "tool.param.replacement_item"))
            ]
        case .queryTasksByMember:
            return [
                "member_id": prop("integer", "tool.param.member_id_for_task"),
                "include_completed": prop("boolean", "tool.param.include_completed_optional"),
                "limit": prop("integer", "tool.param.max_items")
            ]
        case .generateTask:
            return [
                "member_id": prop("integer", "tool.param.member_id_for_task"),
                "user_input": prop("string", "tool.param.user_input_for_extraction"),
                "require_query_first": prop("boolean", "tool.param.require_query_first")
            ]
        case .askUserQuestion:
            return [
                "question": prop("string", "tool.param.ask_user_question"),
                "questions": prop("array", "tool.param.ask_user_questions", items: literalProp("object", td("tool.param.ask_user_question_item"))),
                "options": prop("array", "tool.param.ask_user_options", items: prop("string", "tool.param.ask_user_option_item")),
                "selection_mode": prop("string", "tool.param.ask_user_selection_mode", enumValues: ["single", "multiple"]),
                "allows_other": prop("boolean", "tool.param.ask_user_allows_other")
            ]
        }
    }

    private static func required(for tool: SparkToolName) -> [String] {
        switch tool {
        case .fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails, .fetchSleepDetails, .fetchWorkoutDetails:
            return ["start_date", "end_date"]
        case .makeNutritionData:
            return ["protein", "carbohydrates", "fat", "energy"]
        case .generateStructuredHealthCard:
            return ["report_type", "raw_text"]
        case .getHealthResourceReference:
            return ["resource_type", "resource_id"]
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
        case .getHealthResourceContext, .listMemberHealthSources, .requestMemberSelection, .searchCalendarAndReminders,
             .writeSystemEvent, .queryTasksByMember, .generateChatTitle, .getCurrentMember, .switchMember,
             .findMember, .askUserQuestion:
            return []
        }
    }
}
