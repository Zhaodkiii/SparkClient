import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// 专业版：毛玻璃容器 + `HanlinChatInputView`（与 `ChatComposerView` 无共用视图实现）+ 模型行。
struct HanlinChatComposerView: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var memberContextStore: MemberContextStore
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let boundMemberID: Int?
    let modelRows: [AIScenarioRemoteModelRow]
    let smallTasks: [SmallTask]
    let initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let memberCompleteDataFetcher: any MemberCompleteDataFetching
    let medicalQueryAPI: SparkMedicalQueryAPI
    let fileTransferService: FileTransferService
    let onSend: () -> Void
    let onCancel: () -> Void
    let onSmallTaskTapped: (SmallTask) -> Void
    let onAttachmentsPicked: ([ChatComposerAttachmentPreview]) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onSetMemberBinding: (Int?) -> Void
    let onMaxHealthRefsReached: () -> Void
    let onPresentAskReportPicker: () -> Void
    /// 模型选择变更时立即持久化到线程并触发同步（由 `ChatDetailViewModel.updateThreadModel` 承担）。
    let onPersistSelectedChatModel: (String?) -> Void

    @State private var showFileImporter = false
    @State private var isKeyboardVisible = false

    private var composerDraft: ChatComposerDraft {
        stateStore.composerDraft(for: threadID)
    }

    private var attachmentMenuOpen: Bool {
        composerDraft.isShowingAttachmentMenu
    }

    private var selectedModelRow: AIScenarioRemoteModelRow? {
        guard let selectedName = composerDraft.runtimeFlags.selectedChatModelName else { return nil }
        return modelRows.first { $0.name == selectedName }
    }

    private var showsMediaAttachmentSources: Bool {
        selectedModelRow?.company.uppercased() != "LOCAL"
    }

    private var canOpenCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

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
        VStack(spacing: 4) {
            ChatComposerContextTaskBar(
                boundMemberID: boundMemberID,
                isSending: stateStore.isSending,
                smallTasks: smallTasks,
                onAskReport: onPresentAskReportPicker,
                onSmallTaskTapped: onSmallTaskTapped
            )

            HanlinChatInputView(
                threadID: threadID,
                modelReasoning: modelReasoning,
                stateStore: stateStore,
                memberContextStore: memberContextStore,
                aiSettingsViewModel: aiSettingsViewModel,
                boundMemberID: boundMemberID,
                modelRows: modelRows,
                medicalQueryAPI: medicalQueryAPI,
                initialCompleteData: initialCompleteData,
                memberCompleteDataFetcher: memberCompleteDataFetcher,
                fileTransferService: fileTransferService,
                onSend: onSend,
                onCancel: onCancel,
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

#if DEBUG
            if !isKeyboardVisible {
                ChatComposerModelPickerRow(
                    models: modelRows,
                    selectedModelName: selectedModelBinding
                )
            }
#endif

            if attachmentMenuOpen {
                HanlinAttachmentSourceSelector(
                    showsMediaSources: showsMediaAttachmentSources,
                    attachmentCount: composerDraft.attachments.count,
                    isSending: stateStore.isSending,
                    isVisible: attachmentMenuOpen,
                    showCameraPicker: composerDraft.isShowingCamera,
                    showImagePicker: composerDraft.isShowingPhotoPicker,
                    showDocumentPicker: showFileImporter,
                    onCamera: {
                        guard canOpenCamera else { return }
                        stateStore.setCameraPresented(true, for: threadID)
                    },
                    onPhotos: {
                        stateStore.setPhotoPickerPresented(true, for: threadID)
                    },
                    onFiles: {
                        stateStore.setAttachmentMenuPresented(false, for: threadID)
                        showFileImporter = true
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: attachmentMenuOpen)
//        .padding(.bottom, 12)
        .background(Color(uiColor: .systemBackground))
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
            defer {
                stateStore.setAttachmentMenuPresented(false, for: threadID)
            }
            guard case .success(let urls) = result else { return }
            Task {
                let previews = await ChatComposerAttachmentImporter.importFiles(urls: urls)
                await MainActor.run {
                    onAttachmentsPicked(previews)
                }
            }
        }
    }
}
