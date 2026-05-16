import Foundation
import Combine

@MainActor
final class OnboardingAgentSetupViewModel: ObservableObject {
    @Published var selectedBaseModelName = ""
    @Published private(set) var isCreating = false
    @Published var errorMessage: String?

    private let aiSettingsViewModel: AISettingsViewModel
    private var didLoad = false

    init(aiSettingsViewModel: AISettingsViewModel) {
        self.aiSettingsViewModel = aiSettingsViewModel
    }

    var agents: [AllModels] {
        aiSettingsViewModel.snapshot.allModels
            .filter { $0.identity == .agent }
            .sorted { $0.position < $1.position }
    }

    var baseModels: [AllModels] {
        aiSettingsViewModel.snapshot.allModels
            .filter { $0.identity == .model && $0.supportsText && $0.isEnabled }
            .sorted { $0.position < $1.position }
    }

    var smallTasks: [SmallTask] {
        aiSettingsViewModel.effectiveSmallTasks
    }

    var promptTooling: AISettingsPromptTooling {
        aiSettingsViewModel.promptTooling
    }

    var promptTemplates: [PromptRepo] {
        aiSettingsViewModel.snapshot.promptRepo
    }

    var scenarioBindings: [AIScenarioModelBinding] {
        aiSettingsViewModel.snapshot.scenarioBindings
    }

    func loadIfNeeded() async {
        guard didLoad == false else { return }
        didLoad = true
        await aiSettingsViewModel.load()
        if selectedBaseModelName.isEmpty {
            selectedBaseModelName = baseModels.first?.name ?? ""
        }
    }

    func createAgent(from template: OnboardingAgentTemplate) async -> Bool {
        let baseName = selectedBaseModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard baseName.isEmpty == false else {
            errorMessage = L10n.text("onboarding.agent.error.no_base_model", fallback: "请先添加或启用一个可用于对话的基础模型。")
            return false
        }

        isCreating = true
        defer { isCreating = false }

        let taskCodes = template.relatedTaskCodes.filter { desiredCode in
            smallTasks.contains { $0.code == desiredCode }
        }
        let didCreate = await aiSettingsViewModel.createLocalAgentAndPersist(
            displayName: template.displayName,
            iconSymbol: template.icon,
            baseModelName: baseName,
            systemPrompt: template.systemPrompt,
            aiScenarios: template.scenarios,
            aiToolScenarios: template.tools,
            relatedTaskCodes: taskCodes
        )
        if didCreate == false {
            errorMessage = aiSettingsViewModel.errorMessage
                ?? L10n.text("onboarding.agent.error.create_failed", fallback: "智能体创建失败，请检查基础模型配置。")
        }
        return didCreate
    }

    func createCustomAgent(
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String],
        aiToolScenarios: [String],
        relatedTaskCodes: [String],
        scenarioBindings: [AIScenarioModelBinding]
    ) {
        Task {
            _ = await aiSettingsViewModel.createLocalAgentAndPersist(
                displayName: displayName,
                iconSymbol: iconSymbol,
                baseModelName: baseModelName,
                systemPrompt: systemPrompt,
                aiScenarios: aiScenarios,
                aiToolScenarios: aiToolScenarios,
                relatedTaskCodes: relatedTaskCodes,
                scenarioBindings: scenarioBindings
            )
        }
    }

    func updateAgent(
        id: UUID,
        displayName: String,
        iconSymbol: String,
        baseModelName: String,
        systemPrompt: String,
        aiScenarios: [String],
        aiToolScenarios: [String],
        relatedTaskCodes: [String],
        scenarioBindings: [AIScenarioModelBinding]
    ) {
        Task {
            _ = await aiSettingsViewModel.updateLocalAgentAndPersist(
                id: id,
                displayName: displayName,
                iconSymbol: iconSymbol,
                baseModelName: baseModelName,
                systemPrompt: systemPrompt,
                aiScenarios: aiScenarios,
                aiToolScenarios: aiToolScenarios,
                relatedTaskCodes: relatedTaskCodes,
                scenarioBindings: scenarioBindings
            )
        }
    }

    func persistScenarioBindingChange(_ change: ModelScenarioBindingPersistenceChange) {
        Task {
            _ = await aiSettingsViewModel.persistScenarioBindingChange(change)
        }
    }

    func deleteAgent(_ agent: AllModels) {
        Task {
            _ = await aiSettingsViewModel.removeLocalModelAndPersist(agent)
        }
    }
}

struct OnboardingAgentTemplate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let summary: String
    let quote: String
    let icon: String
    let tint: AgentTemplateTint
    let systemPrompt: String
    let tools: [String]
    let scenarios: [String]
    let relatedTaskCodes: [String]
}

struct AgentTemplateTint: Equatable {
    let primary: String
    let secondary: String
}

enum OnboardingAgentTemplates {
    static let all: [OnboardingAgentTemplate] = [
        .privateDoctor,
        .healthButler,
        .fitnessCoach,
        .sleepOptimizer
    ]
}

private extension OnboardingAgentTemplate {
    static let healthTools = [
        SparkToolName.fetchStepDetails.rawValue,
        SparkToolName.fetchEnergyDetails.rawValue,
        SparkToolName.fetchWorkoutDetails.rawValue,
        SparkToolName.fetchSleepDetails.rawValue,
        SparkToolName.fetchNutritionDetails.rawValue,
        SparkToolName.makeNutritionData.rawValue,
        SparkToolName.generateStructuredHealthCard.rawValue,
        SparkToolName.getCurrentMember.rawValue,
        SparkToolName.queryMemberProfile.rawValue
    ]

    static let knowledgeTools = [
        SparkToolName.searchKnowledgeBag.rawValue,
        SparkToolName.createKnowledgeDocument.rawValue
    ]

    static let memoryTools = [
        SparkToolName.saveMemory.rawValue,
        SparkToolName.retrieveMemory.rawValue,
        SparkToolName.updateMemory.rawValue
    ]

    static let webTools = [
        SparkToolName.searchOnline.rawValue,
        SparkToolName.readWebPage.rawValue,
        SparkToolName.searchArxivPapers.rawValue
    ]

    static let privateDoctor = OnboardingAgentTemplate(
        id: "private_doctor",
        displayName: "私人医生助理",
        summary: "解读报告、梳理用药和健康风险，回答时更严谨。",
        quote: "我会结合健康记录和知识来源，帮你把复杂医学信息讲清楚。",
        icon: "stethoscope",
        tint: AgentTemplateTint(primary: "#2563EB", secondary: "#6366F1"),
        systemPrompt: "你是一位专业、严谨的私人医生助理。你擅长结合用户的体征、用药、检验、诊断和病历信息，给出清晰、准确、可执行的解读与建议。你必须避免夸大结论，不替代医生诊断；遇到急症、严重异常或不确定情况时，应建议用户及时就医。回答要结构清楚，必要时说明依据和下一步行动。",
        tools: healthTools + knowledgeTools + memoryTools + webTools,
        scenarios: [AIScenario.chat.rawValue, AIScenario.reportInterpretation.rawValue],
        relatedTaskCodes: ["today_activity_summary", "today_sleep_summary", "memory_search", "knowledge_search"]
    )

    static let healthButler = OnboardingAgentTemplate(
        id: "health_butler",
        displayName: "健康管家",
        summary: "跟踪饮食、睡眠和日常活动，偏生活方式管理。",
        quote: "我会把你的日常数据整理成更容易坚持的健康计划。",
        icon: "fork.knife",
        tint: AgentTemplateTint(primary: "#059669", secondary: "#0EA5E9"),
        systemPrompt: "你是一位贴心的健康管家，专注饮食、睡眠、活动和日常起居。你会根据用户的营养、睡眠、步数、能量和成员资料，给出温和、可执行的生活方式建议。回答应鼓励用户形成稳定习惯，避免制造焦虑；涉及医疗诊断时应保持谨慎并建议咨询专业医生。",
        tools: [
            SparkToolName.fetchNutritionDetails.rawValue,
            SparkToolName.makeNutritionData.rawValue,
            SparkToolName.fetchSleepDetails.rawValue,
            SparkToolName.fetchEnergyDetails.rawValue,
            SparkToolName.fetchStepDetails.rawValue,
            SparkToolName.getCurrentMember.rawValue
        ] + knowledgeTools + memoryTools,
        scenarios: [AIScenario.chat.rawValue],
        relatedTaskCodes: ["today_nutrition_summary", "today_sleep_summary", "today_activity_summary"]
    )

    static let fitnessCoach = OnboardingAgentTemplate(
        id: "fitness_coach",
        displayName: "运动教练",
        summary: "围绕训练、恢复和活动趋势给出建议。",
        quote: "我会根据运动和恢复状态，帮你安排更合理的训练节奏。",
        icon: "figure.run",
        tint: AgentTemplateTint(primary: "#EA580C", secondary: "#F97316"),
        systemPrompt: "你是一位专业的运动教练助手。你会结合用户的步数、运动、能量消耗、睡眠与营养数据，给出训练安排、恢复提醒和饮食配合建议。回答应具体、量力而行，并提示用户在疼痛、胸闷、头晕或疾病风险下先咨询专业人士。",
        tools: [
            SparkToolName.fetchStepDetails.rawValue,
            SparkToolName.fetchEnergyDetails.rawValue,
            SparkToolName.fetchWorkoutDetails.rawValue,
            SparkToolName.fetchSleepDetails.rawValue,
            SparkToolName.fetchNutritionDetails.rawValue,
            SparkToolName.generateStructuredHealthCard.rawValue
        ] + knowledgeTools,
        scenarios: [AIScenario.chat.rawValue],
        relatedTaskCodes: ["today_activity_summary", "today_sleep_summary", "today_nutrition_summary"]
    )

    static let sleepOptimizer = OnboardingAgentTemplate(
        id: "sleep_optimizer",
        displayName: "睡眠优化师",
        summary: "分析睡眠、活动和作息，帮助改善睡眠质量。",
        quote: "我会帮你找到影响睡眠的模式，并给出可执行的调整建议。",
        icon: "moon.zzz.fill",
        tint: AgentTemplateTint(primary: "#0EA5E9", secondary: "#38BDF8"),
        systemPrompt: "你是一位专注睡眠与作息的健康助手。你会结合用户的睡眠、活动、营养和日常习惯，分析睡眠质量与影响因素，给出睡前习惯、日间活动和作息调整建议。语气应平和、具体，避免绝对化承诺；长期严重失眠或伴随明显症状时，应建议用户寻求专业帮助。",
        tools: [
            SparkToolName.fetchSleepDetails.rawValue,
            SparkToolName.fetchEnergyDetails.rawValue,
            SparkToolName.fetchStepDetails.rawValue,
            SparkToolName.fetchNutritionDetails.rawValue,
            SparkToolName.getCurrentMember.rawValue
        ] + knowledgeTools + memoryTools,
        scenarios: [AIScenario.chat.rawValue],
        relatedTaskCodes: ["today_sleep_summary", "today_activity_summary"]
    )
}
