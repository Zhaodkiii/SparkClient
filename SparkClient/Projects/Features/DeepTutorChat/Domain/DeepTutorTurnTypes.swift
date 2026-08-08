import Foundation

/// Turn 恢复模式，对齐 DeepTutor-main 的 turn lifecycle。
nonisolated enum DeepTutorTurnResumeMode: String, Codable, Sendable, Equatable {
    case liveSend
    case replaySnapshot
    case askUserResume
    case memberSelectionResume
}

/// Capability 阶段定义，表达多阶段 pipeline。
nonisolated enum DeepTutorCapabilityStage: String, Codable, Sendable, CaseIterable, Equatable {
    case exploring
    case responding
    case rephrasing
    case decomposing
    case researching
    case reporting
    case animating
    case visualizing
    case teaching
}

nonisolated extension DeepTutorCapability {
    var stagePipeline: [DeepTutorCapabilityStage] {
        switch self {
        case .chat:
            return [.exploring, .responding]
        case .deepResearch:
            return [.rephrasing, .decomposing, .researching, .reporting]
        case .deepQuestion:
            return [.exploring, .teaching, .responding]
        case .mathAnimator:
            return [.exploring, .animating, .responding]
        case .visualize:
            return [.exploring, .visualizing, .responding]
        case .masteryPath:
            return [.exploring, .teaching, .responding]
        }
    }

    var initialStage: DeepTutorCapabilityStage {
        stagePipeline.first ?? .responding
    }
}

/// 一次 turn 的完整编排计划：模型、能力、工具、prompt、快照与执行意图。
nonisolated struct DeepTutorTurnPlan: Sendable {
    enum Intent: Sendable, Equatable {
        case send(userText: String)
        case retryAssistant(assistantMessageID: UUID, userMessageID: UUID)
        case regenerate(assistantMessageID: UUID, userMessageID: UUID)
    }

    let turnID: UUID
    let conversationID: UUID
    let capability: DeepTutorCapability
    let capabilityStage: DeepTutorCapabilityStage
    let resumeMode: DeepTutorTurnResumeMode
    let modelResolutionMode: DeepTutorModelContextResolver.ResolutionMode
    let intent: Intent
    let modelContext: DeepTutorResolvedModelContext
    let builtRequest: DeepTutorRuntimeRequestBuilder.BuiltRequest?
    let snapshot: DeepTutorRequestSnapshot
    let conversation: DeepTutorConversation?
    let settings: DeepTutorConversationGenerationSettings
    let conversationTitle: String
    let userInput: String
    let visibleHistory: [DeepTutorMessage]
    let boundMemberID: Int?
}
