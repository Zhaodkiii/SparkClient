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
    let onSend: () -> Void
    let onCancel: () -> Void
    let onSmallTaskTapped: (SmallTask) -> Void
    let onAttachmentsPicked: ([ChatComposerAttachmentPreview]) -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onSetMemberBinding: (Int?) -> Void
    /// 模型选择变更时立即持久化到线程并触发同步（由 `ChatDetailViewModel.updateThreadModel` 承担）。
    let onPersistSelectedChatModel: (String?) -> Void

    @State private var showFileImporter = false

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
                    smallTasks: smallTasks,
                    onSmallTaskTapped: onSmallTaskTapped
                )
                
                HanlinChatInputView(
                    threadID: threadID,
                    modelReasoning: modelReasoning,
                    stateStore: stateStore,
                    memberContextStore: memberContextStore,
                    boundMemberID: boundMemberID,
                    onSend: onSend,
                    onCancel: onCancel,
                    onRequestFileImport: { showFileImporter = true },
                    onAttachmentsPicked: onAttachmentsPicked,
                    onRemoveAttachment: onRemoveAttachment,
                    onSetMemberBinding: onSetMemberBinding
                )

//                ChatComposerModelPickerRow(
//                    models: modelRows,
//                    selectedModelName: selectedModelBinding
//                )
            }
            .padding(.bottom, 12)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.primary.opacity(0.32), radius: 1)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 15)
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
    }
}
