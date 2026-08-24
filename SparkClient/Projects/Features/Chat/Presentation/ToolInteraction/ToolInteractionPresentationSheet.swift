import SwiftUI

/// 当前队列中的工具交互（全局 sheet，不写入消息流）。
struct ToolInteractionPresentationSheet: View {
    let active: ToolInteractionCoordinator.ActivePresentation
    @ObservedObject var coordinator: ToolInteractionCoordinator
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var listViewModel: ChatListViewModel
    @ObservedObject var detailViewModel: ChatDetailViewModel
    let knowledgeDependencies: KnowledgeFeatureDependencies
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @ObservedObject var taskManager: TaskManager
    @ObservedObject var homeViewModel: HomeViewModel
    let toolPreviewRenderContext: ChatRenderContext?
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let memberCompleteDataFetcher: any MemberCompleteDataFetching
    let guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder?
    let onClearToolPreviewRenderContext: () -> Void
    let onSaveSystemMessage: (SystemMessageSettingsPrompt, String) -> Void
    let onAskReportAppend: (UUID, [HealthResourceRef]) -> Void
    let onAskReportSetMemberBinding: (Int?) -> Void
    let onAskReportMaxRefsReached: () -> Void
    let onConversationThreadSelected: (UUID) -> Void

    var body: some View {
        switch active.snapshot {
        case .consent(let prompt):
            ExternalToolDataConsentSheet(
                prompt: prompt,
                onAllow: { coordinator.completeConsent(id: active.id, allowed: true) },
                onAllowAlways: { coordinator.completeConsent(id: active.id, allowed: true, rememberTool: true) },
                onDeny: { coordinator.completeConsent(id: active.id, allowed: false) }
            )
        case .question(let prompt):
            ToolQuestionSheet(
                prompt: prompt,
                onSubmit: { coordinator.completeQuestion(id: active.id, answer: ToolQuestionAnswer(responses: $0)) },
                onCancel: { coordinator.completeQuestionCancelled(id: active.id) }
            )
        case .member(let prompt):
            MemberSelectionToolSheet(
                prompt: prompt,
                memberContextStore: memberContextStore,
                onSubmit: { coordinator.completeMemberSelection(id: active.id, memberID: $0) },
                onCancel: { coordinator.completeMemberCancelled(id: active.id) }
            )
        case .toolPreview(let prompt):
            ToolPreviewSheet(
                prompt: prompt,
                renderContext: toolPreviewRenderContext,
                coordinator: coordinator,
                stateStore: stateStore,
                onClearRenderContext: onClearToolPreviewRenderContext
            )
        case .systemMessageSettings(let prompt):
            SystemMessageSettingsSheet(
                prompt: prompt,
                onSave: { value in
                    onSaveSystemMessage(prompt, value)
                    coordinator.dismissSystemMessageSettings(id: active.id)
                },
                onClose: { coordinator.dismissSystemMessageSettings(id: active.id) }
            )
        case .healthResourceCandidates(let prompt):
            let pendingCount = stateStore.composerDraft(for: prompt.threadID).pendingHealthResourceRefs.count
            let remaining = max(0, min(prompt.maxSelectable, HealthResourceSendValidator.maxRefs - pendingCount))
            ChatHealthSourceCandidateSheet(
                candidates: prompt.candidates,
                maxSelectable: max(1, remaining),
                onConfirm: { picked in
                    coordinator.completeHealthResourceCandidates(id: active.id, selected: picked)
                },
                onCancel: {
                    coordinator.completeHealthResourceCandidatesCancelled(id: active.id)
                }
            )
        case .askReportPicker(let prompt):
            ChatAskReportSheet(
                memberContextStore: memberContextStore,
                boundMemberID: prompt.memberID,
                pendingRefs: stateStore.composerDraft(for: prompt.threadID).pendingHealthResourceRefs,
                initialCompleteData: initialCompleteData,
                memberCompleteDataFetcher: memberCompleteDataFetcher,
                onAppendToPreview: { refs in
                    onAskReportAppend(active.id, refs)
                },
                onSetMemberBinding: onAskReportSetMemberBinding,
                onMaxRefsReached: onAskReportMaxRefsReached
            )
        case .apiKeysSettings:
            CompatibleNavigationContainer(legacyStackStyle: true) {
                APIKeysSettingsView(viewModel: aiSettingsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.done")) {
                                coordinator.dismissAPIKeysSettings(id: active.id)
                            }
                        }
                    }
            }
        case .conversationList:
            ChatConversationListPage(
                stateStore: stateStore,
                listViewModel: listViewModel,
                detailViewModel: detailViewModel,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                taskManager: taskManager,
                homeViewModel: homeViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                pushAdapter: nil,
                guideHomeDestinationBuilder: guideHomeDestinationBuilder,
                onThreadSelected: { selectedThreadID in
                    onConversationThreadSelected(selectedThreadID)
                    coordinator.dismissConversationList(id: active.id)
                },
                onPresentChat: { _ in }
            )
            .presentationDetents([.fraction(0.80)])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
        }
    }
}
