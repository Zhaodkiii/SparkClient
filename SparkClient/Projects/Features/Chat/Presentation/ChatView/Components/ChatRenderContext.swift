import SwiftUI

/// 引导卡片滑块 → 健康首页 destination 构造器（CHAT-000025）。
/// 由 App 宿主注入：把滑块类别变成消息内 NavigationLink 的 destination；
/// payload 模型与 Chat 业务层不感知首页依赖细节。
typealias ChatGuideHomeDestinationBuilder = (ChatGuideMetricCategory) -> AnyView

/// 健康滑块实时刷新结果：成员上下文必须来自当前 thread，而不是消息 payload 快照。
struct ChatGuideMetricReloadResult: Sendable {
    let threadID: UUID
    let memberID: Int?
    let sections: [ChatGuideMetricSection]
}

typealias ChatGuideMetricSectionsProvider = (UUID) async -> ChatGuideMetricReloadResult?

/// 聊天消息渲染上下文
/// 承载渲染消息块所需的所有数据、状态、回调，统一传递给各个 UI 组件
struct ChatRenderContext {
    // MARK: - 基础数据
    let message: ChatMessage                               // 当前要渲染的聊天消息本体
    let isLastAssistantMessage: Bool                       // 是否是最后一条助手消息（用于控制样式/展开逻辑）
    let isMathMode: Bool                                   // 是否为数学公式模式（渲染等宽文本）
    let conversationCardStyle: ChatConversationCardStyle
    let toolTraceDisplayMode: ChatToolTraceDisplayMode
    let collapseToolsWhileStreaming: Bool
    
    // MARK: - 加载/保存状态 ID 集合
    let taskCardLoadingIDs: Set<Int>                       // 正在加载中的任务卡片 ID 集合
    let savingKnowledgeCardIDs: Set<UUID>                  // 正在保存中的知识库卡片 ID
    let savedKnowledgeCardIDs: Set<UUID>                   // 已保存的知识库卡片 ID
    let savingStructuredHealthCardIDs: Set<UUID>           // 正在保存的结构化健康卡片 ID
    let savingNutritionCardIDs: Set<UUID>                  // 正在写入 Apple 健康的营养卡片 ID
    let guideSendingQuestionIDs: Set<String>               // 引导卡片发送中的问题 ID（按钮置灰）
    
    // MARK: - 全局依赖
    let memberContextStore: MemberContextStore             // 成员上下文数据仓库
    let knowledgeDependencies: KnowledgeFeatureDependencies
    let knowledgeViewModel: KnowledgeLibraryViewModel
    
    // MARK: - 展示文本
    let errorCardBodyText: String                          // 错误卡片默认提示文本
    
    // MARK: - 用户操作回调（事件响应）
    let onRetry: () -> Void                                // 重试按钮点击（发送失败时）
    let onSaveKnowledgeCard: (ChatKnowledgeCard) -> Void   // 保存知识库卡片
    let onKnowledgeCardSaved: (ChatKnowledgeCard) -> Void
    let onTaskCardAction: (TaskCard.Action) -> Void        // 任务卡片操作（完成/删除等）
    let onTaskCardOpen: (TaskCard, ChatMessage) -> Void
    let onTaskCardPreviewSave: (TaskCardPreviewContext, TaskCard) async throws -> HealthTask
    let onTaskCardPreviewEdit: (TaskCardPreviewContext, TaskCardPreviewEditResult) async -> Void
    let onPendingMemberToolSelect: (PendingMemberToolCard, Int?) -> Void  // 待处理成员工具选择
    let onToolQuestionCardSubmit: (ChatToolQuestionCard, [ToolQuestionResponse]) -> Void
    let onToolMemberSelectionCardSubmit: (ChatToolMemberSelectionCard, Int) -> Void
    let onHealthResourceCandidateCardChoose: (ChatHealthResourceCandidateSelectionCard) -> Void
    let onHealthResourceCandidateCardSkip: (ChatHealthResourceCandidateSelectionCard) -> Void
    let onToolConsentCardAllow: (ChatToolConsentCard) -> Void
    let onToolConsentCardDeny: (ChatToolConsentCard) -> Void
    let onToolConsentCardShowDetails: (ChatToolConsentCard) -> Void
    let onToolConsentCardOpenSettings: (ChatToolConsentCard) -> Void
    let onLocationPermissionCardAction: (ChatLocationPermissionCard) -> Void
    let onWeatherConfigCardOpen: (ChatWeatherConfigCardPayload) -> Void
    let onStructuredHealthCardAction: (ChatStructuredHealthCardAction) -> Void  // 健康卡片操作
    let onStructuredHealthCardOpenPreview: (UUID, ChatStructuredHealthCardItem, ChatMessage) -> Void
    let onNutritionCardAction: (ChatNutritionCardAction) -> Void                // 营养卡片操作
    let onCaptureAttachmentsPicked: (ChatCaptureMessageCardPayload, [ChatComposerAttachmentPreview]) -> Void
    let onCaptureCancel: (ChatCaptureMessageCardPayload) -> Void
    let onSmallTaskCardOpen: (ChatSmallTaskMessageCardPayload) -> Void
    /// 引导卡片科普问题点击（上抛给 ViewModel 走当前会话发送链路）。
    let onGuideQuestionTap: (ChatGuideQuestion) -> Void
    /// 线上问诊消息卡片点击 → 打开问诊详情。
    let onConsultationCardTap: (ChatConsultationCardPayload) -> Void
    /// 引导卡片滑块点击 → 健康首页 destination（CHAT-000025）。
    /// nil（宿主未注入 / 旧宿主）时滑块降级为纯展示面板，不影响问题点击。
    var guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil
    var guideMetricSectionsProvider: ChatGuideMetricSectionsProvider? = nil
    /// 展示工具详情全局 Sheet（由消息行注入，传入预览载荷与当前渲染上下文）。
    let onPresentToolPreview: (ToolPreviewPrompt, ChatRenderContext) -> Void

    /// 附件缓存/下载（对齐 ``MedicalAttachmentGridPreview`` 的 ``FileTransferService`` 用法）。
    let fileTransferService: FileTransferService

    /// 健康资料卡片摘要懒加载（按类型+ID 单条查询，不拉 complete-data 全量）。
    let medicalQueryAPI: SparkMedicalQueryAPI
    /// 首页/问报告已缓存的成员 complete-data，仅作本地命中加速。
    let cachedMemberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    /// 本条消息内健康资料引用块总数（用于 `n/总数`）。
    let healthResourceReferenceCount: Int
    let onHealthResourceUnavailableTap: () -> Void
    let healthResourceDestinationFactory: (HealthResourceReference) -> AnyView
    let onHeightChangingUpdate: (@escaping () -> Void) -> Void
}

extension ChatRenderContext {
    /// 用最新消息替换上下文（回调与 UI 状态保持不变），供工具详情 Sheet 等场景使用。
    func replacingMessage(_ message: ChatMessage) -> ChatRenderContext {
        ChatRenderContext(
            message: message,
            isLastAssistantMessage: isLastAssistantMessage,
            isMathMode: isMathMode,
            conversationCardStyle: conversationCardStyle,
            toolTraceDisplayMode: toolTraceDisplayMode,
            collapseToolsWhileStreaming: collapseToolsWhileStreaming,
            taskCardLoadingIDs: taskCardLoadingIDs,
            savingKnowledgeCardIDs: savingKnowledgeCardIDs,
            savedKnowledgeCardIDs: savedKnowledgeCardIDs,
            savingStructuredHealthCardIDs: savingStructuredHealthCardIDs,
            savingNutritionCardIDs: savingNutritionCardIDs,
            guideSendingQuestionIDs: guideSendingQuestionIDs,
            memberContextStore: memberContextStore,
            knowledgeDependencies: knowledgeDependencies,
            knowledgeViewModel: knowledgeViewModel,
            errorCardBodyText: errorCardBodyText,
            onRetry: onRetry,
            onSaveKnowledgeCard: onSaveKnowledgeCard,
            onKnowledgeCardSaved: onKnowledgeCardSaved,
            onTaskCardAction: onTaskCardAction,
            onTaskCardOpen: onTaskCardOpen,
            onTaskCardPreviewSave: onTaskCardPreviewSave,
            onTaskCardPreviewEdit: onTaskCardPreviewEdit,
            onPendingMemberToolSelect: onPendingMemberToolSelect,
            onToolQuestionCardSubmit: onToolQuestionCardSubmit,
            onToolMemberSelectionCardSubmit: onToolMemberSelectionCardSubmit,
            onHealthResourceCandidateCardChoose: onHealthResourceCandidateCardChoose,
            onHealthResourceCandidateCardSkip: onHealthResourceCandidateCardSkip,
            onToolConsentCardAllow: onToolConsentCardAllow,
            onToolConsentCardDeny: onToolConsentCardDeny,
            onToolConsentCardShowDetails: onToolConsentCardShowDetails,
            onToolConsentCardOpenSettings: onToolConsentCardOpenSettings,
            onLocationPermissionCardAction: onLocationPermissionCardAction,
            onWeatherConfigCardOpen: onWeatherConfigCardOpen,
            onStructuredHealthCardAction: onStructuredHealthCardAction,
            onStructuredHealthCardOpenPreview: onStructuredHealthCardOpenPreview,
            onNutritionCardAction: onNutritionCardAction,
            onCaptureAttachmentsPicked: onCaptureAttachmentsPicked,
            onCaptureCancel: onCaptureCancel,
            onSmallTaskCardOpen: onSmallTaskCardOpen,
            onGuideQuestionTap: onGuideQuestionTap,
            onConsultationCardTap: onConsultationCardTap,
            guideHomeDestinationBuilder: guideHomeDestinationBuilder,
            guideMetricSectionsProvider: guideMetricSectionsProvider,
            onPresentToolPreview: onPresentToolPreview,
            fileTransferService: fileTransferService,
            medicalQueryAPI: medicalQueryAPI,
            cachedMemberCompleteData: cachedMemberCompleteData,
            healthResourceReferenceCount: healthResourceReferenceCount,
            onHealthResourceUnavailableTap: onHealthResourceUnavailableTap,
            healthResourceDestinationFactory: healthResourceDestinationFactory,
            onHeightChangingUpdate: onHeightChangingUpdate
        )
    }
}
