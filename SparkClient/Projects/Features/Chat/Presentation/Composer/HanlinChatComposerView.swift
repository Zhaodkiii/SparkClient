import SwiftUI
import UniformTypeIdentifiers

/// 专业版：毛玻璃容器 + `HanlinChatInputView`（与 `ChatComposerView` 无共用视图实现）+ 模型行。
struct HanlinChatComposerView: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var memberContextStore: MemberContextStore
    let boundMemberID: Int?
    let modelRows: [AIScenarioRemoteModelRow]
    let smallTasks: [SmallTask]
    let initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let fetchMemberCompleteData: (Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData
    let medicalQueryAPI: SparkMedicalQueryAPI
    let fileTransferService: FileTransferService
    let onSend: () -> Void
    let onCancel: () -> Void
    let onSmallTaskTapped: (SmallTask) -> Void
    let onAttachmentsPicked: ([ChatComposerAttachmentPreview]) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onSetMemberBinding: (Int?) -> Void
    let onMaxHealthRefsReached: () -> Void
    /// 模型选择变更时立即持久化到线程并触发同步（由 `ChatDetailViewModel.updateThreadModel` 承担）。
    let onPersistSelectedChatModel: (String?) -> Void

    @State private var showFileImporter = false
    @State private var showAskReportSheet = false
    @State private var isKeyboardVisible = false

    private var selectedModelBinding: Binding<String?> {
        Binding(
            get: { stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName },
            set: { newValue in
                stateStore.setSelectedChatModelName(newValue, for: threadID)
                onPersistSelectedChatModel(newValue)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ChatComposerContextTaskBar(
                    boundMemberID: boundMemberID,
                    isSending: stateStore.isSending,
                    smallTasks: smallTasks,
                    onAskReport: { showAskReportSheet = true },
                    onSmallTaskTapped: onSmallTaskTapped
                )

                HanlinChatInputView(
                    threadID: threadID,
                    modelReasoning: modelReasoning,
                    stateStore: stateStore,
                    memberContextStore: memberContextStore,
                    boundMemberID: boundMemberID,
                    medicalQueryAPI: medicalQueryAPI,
                    initialCompleteData: initialCompleteData,
                    fetchMemberCompleteData: fetchMemberCompleteData,
                    fileTransferService: fileTransferService,
                    onSend: onSend,
                    onCancel: onCancel,
                    onRequestFileImport: { showFileImporter = true },
                    onAttachmentsPicked: onAttachmentsPicked,
                    onRemoveAttachment: onRemoveAttachment,
                    onSetMemberBinding: onSetMemberBinding,
                    onRemoveHealthResourceRef: { ref in
                        stateStore.removeHealthResourceRef(ref, for: threadID)
                    },
                    onClearHealthResourceRefs: {
                        stateStore.clearHealthResourceRefs(for: threadID)
                    }
                )

                if !isKeyboardVisible {
                    ChatComposerModelPickerRow(
                        models: modelRows,
                        selectedModelName: selectedModelBinding
                    )
                }
            }
            .padding(.bottom, 12)
            .background {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.primary.opacity(0.32), radius: 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isKeyboardVisible = false
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .image, .jpeg, .png],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                let previews = await ChatComposerAttachmentImporter.importFiles(urls: urls)
                await MainActor.run {
                    onAttachmentsPicked(previews)
                }
            }
        }
        .sheet(isPresented: $showAskReportSheet) {
            if let memberID = boundMemberID, memberID > 0 {
                ChatAskReportSheet(
                    memberContextStore: memberContextStore,
                    boundMemberID: memberID,
                    pendingRefs: stateStore.composerDraft(for: threadID).pendingHealthResourceRefs,
                    initialCompleteData: initialCompleteData,
                    fetchCompleteData: fetchMemberCompleteData,
                    onAppendToPreview: { refs in
                        let draft = stateStore.composerDraft(for: threadID)
                        let remaining = HealthResourceSendValidator.maxRefs - draft.pendingHealthResourceRefs.count
                        guard remaining > 0 else {
                            onMaxHealthRefsReached()
                            return
                        }
                        let batch = Array(refs.prefix(remaining))
                        if batch.isEmpty {
                            onMaxHealthRefsReached()
                            return
                        }
                        stateStore.appendHealthResourceRefs(batch, for: threadID)
                    },
                    onSetMemberBinding: onSetMemberBinding,
                    onMaxRefsReached: onMaxHealthRefsReached
                )
            }
        }
    }
}
