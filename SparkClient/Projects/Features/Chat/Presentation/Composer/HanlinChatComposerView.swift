import SwiftUI
import UniformTypeIdentifiers

/// 专业版：毛玻璃容器 + `HanlinChatInputView`（与 `ChatComposerView` 无共用视图实现）+ 模型行。
struct HanlinChatComposerView: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore
    let modelRows: [ChatComposerModelOption]
    let onSend: () -> Void

    @State private var showFileImporter = false

    private var selectedModelBinding: Binding<String?> {
        Binding(
            get: { stateStore.composerDraft(for: threadID).runtimeFlags.selectedChatModelName },
            set: { stateStore.setSelectedChatModelName($0, for: threadID) }
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
                    onRequestFileImport: { showFileImporter = true }
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
                    imageData: data,
                    displayName: url.lastPathComponent
                )
            )
        }
        await MainActor.run {
            stateStore.appendComposerAttachments(previews, for: threadID)
        }
    }
}
