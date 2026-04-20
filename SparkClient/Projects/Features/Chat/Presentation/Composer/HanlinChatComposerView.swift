import SwiftUI
import UniformTypeIdentifiers

/// 专业版：毛玻璃容器 + `HanlinChatInputView`（与 `ChatComposerView` 无共用视图实现）+ 模型行。
struct HanlinChatComposerView: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore
    let modelRows: [ChatComposerModelOption]
    let onSend: () -> Void
    let onAttachmentsPicked: ([ChatComposerAttachmentPreview]) -> Void
    let onRemoveAttachment: (UUID) -> Void
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
                HanlinChatInputView(
                    threadID: threadID,
                    modelReasoning: modelReasoning,
                    stateStore: stateStore,
                    onSend: onSend,
                    onRequestFileImport: { showFileImporter = true },
                    onAttachmentsPicked: onAttachmentsPicked,
                    onRemoveAttachment: onRemoveAttachment
                )

                ChatComposerModelPickerRow(
                    models: modelRows,
                    selectedModelName: selectedModelBinding
                )
            }
            .padding(.bottom, 12)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.primary.opacity(0.12), radius: 1)
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
                await importFiles(urls: urls)
            }
        }
    }

    private func importFiles(urls: [URL]) async {
        var previews: [ChatComposerAttachmentPreview] = []
        for url in urls {
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url), data.isEmpty == false else { continue }
            previews.append(
                ChatComposerAttachmentPreview(
                    source: .document,
                    kind: {
                        let inferredType = UTType(filenameExtension: url.pathExtension)
                        if inferredType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
                            return .pdf
                        }
                        if inferredType?.conforms(to: .image) == true {
                            return .image
                        }
                        return .file
                    }(),
                    data: data,
                    displayName: url.lastPathComponent,
                    mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
                    utTypeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier
                )
            )
        }
        await MainActor.run {
            onAttachmentsPicked(previews)
        }
    }
}
