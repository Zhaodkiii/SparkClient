import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 知识写作页（对齐 Health `KnowledgeWritingView` 布局：ZStack + 底部毛玻璃工具区）

/// 单篇知识文档主界面：编辑/预览切换、底部工具栏、网页内联导入、预览态向量化。
/// 依赖注入：`AppContainer.makeKnowledgeDocumentEditorViewModel`；不在 View 内直接访问 Core Data / URLSession。
struct KnowledgeDocumentDetailView: View {
    @ObservedObject var libraryViewModel: KnowledgeLibraryViewModel
    let documentID: UUID

    @StateObject private var editor: KnowledgeDocumentEditorViewModel
    @State private var showDeleteConfirmation = false
    @State private var showFileImporter = false
    /// 与 Health 一致：展开网页 URL 输入条（非 Alert）。
    @State private var showWebInputRow = false
    @State private var webInlineInput = ""
    @State private var showImageSourcePicker = false
    @State private var imagePickerSource: KnowledgeImagePicker.Source = .photoLibrary
    @State private var showImagePicker = false
    /// 导航栏标题：点标题进入 `TextField` 编辑（Health 为 ZStack 切换）。
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(appContainer: AppContainer, viewModel: KnowledgeLibraryViewModel, documentID: UUID) {
        self.libraryViewModel = viewModel
        self.documentID = documentID
        _editor = StateObject(wrappedValue: appContainer.makeKnowledgeDocumentEditorViewModel(documentID: documentID))
    }

    var body: some View {
        primaryContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationToolbarContent }
            .task {
                await loadTask()
            }
            .onChange(of: editor.title) { _ in editor.scheduleDebouncedSave() }
            .onChange(of: editor.bodyText) { _ in editor.scheduleDebouncedSave() }
            .modifier(FileImportOnlyModifier(showFileImporter: $showFileImporter) { url in
                Task { await editor.importFromFile(url: url) }
            })
            .modifier(ImageOCRModifier(
                showImageSourcePicker: $showImageSourcePicker,
                showImagePicker: $showImagePicker,
                imagePickerSource: $imagePickerSource,
                onImage: { image in Task { await editor.appendFromOCR(image: image) } }
            ))
            .modifier(DeleteConfirmModifier(
                showDeleteConfirmation: $showDeleteConfirmation,
                onDelete: {
                    Task {
                        if await editor.deleteDocument() {
                            await libraryViewModel.refresh()
                            dismiss()
                        }
                    }
                }
            ))
            .modifier(EditorErrorAlertModifier(editor: editor))
    }

    // MARK: - 子视图

    private var primaryContent: some View {
        Group {
            if editor.isLoading {
                ProgressView(L10n.text("knowledge.loading"))
            } else if editor.document == nil {
                missingDocument
            } else {
                writingPageLayout
            }
        }
    }

    /// Health 同款：主内容 + 底部悬浮毛玻璃面板（编辑：工具栏；预览：向量化）。
    private var writingPageLayout: some View {
        ZStack(alignment: .bottom) {
            textOrPreviewSection
                .padding(.horizontal, 12)
                .padding(.bottom, editor.isEditMode ? 150 : 170)

            bottomChrome
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
    }

    /// 底部工具区：圆角 + 材质 + 轻阴影，贴近 Health `GlassView` 层次。
    private var bottomChrome: some View {
        VStack(spacing: 12) {
            if editor.isEditMode {
                if showWebInputRow {
                    KnowledgeWebInlineRow(
                        text: $webInlineInput,
                        isBusy: editor.textProcessingInProgress,
                        onSubmit: {
                            Task {
                                await editor.appendWebContent(from: webInlineInput)
                                webInlineInput = ""
                                showWebInputRow = false
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                KnowledgeTextEditToolbar(
                    characterCount: editor.characterCount,
                    tokenEstimate: editor.tokenEstimate,
                    isBusy: editor.textProcessingInProgress,
                    onPolish: { Task { await editor.polish() } },
                    onTranslate: { Task { await editor.translate() } },
                    onOCR: { showImageSourcePicker = true },
                    onImportFile: { showFileImporter = true },
                    onToggleWebPanel: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                            showWebInputRow.toggle()
                        }
                    },
                    onClear: { editor.clearBody() }
                )
            } else {
                KnowledgeEmbeddingPanel(
                    models: editor.embeddingModels,
                    selectedModelName: $editor.selectedEmbeddingModelName,
                    isIndexed: editor.document?.isEmbeddingIndexed ?? false,
                    lastModelName: editor.document?.lastEmbeddingModelName,
                    isBuilding: editor.embeddingInProgress,
                    onBuild: { Task { await editor.buildEmbeddings() } }
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.accentColor.opacity(0.18), radius: 1, x: 0, y: 1)
        )
    }

    private var textOrPreviewSection: some View {
        Group {
            if editor.isEditMode {
                textEditorContent
            } else {
                ScrollView {
                    MarkdownDocumentView(text: editor.bodyText, style: .documentation)
                        .padding(.bottom, 24)
                }
                .modifier(HiddenScrollIndicatorsIfAvailable())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var textEditorContent: some View {
        if #available(iOS 16.0, *) {
            TextEditor(text: $editor.bodyText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.bottom, 8)
        } else {
            TextEditor(text: $editor.bodyText)
                .font(.body)
                .padding(.bottom, 8)
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ZStack {
                Button {
                    titleDraft = editor.title
                    isEditingTitle = true
                    titleFieldFocused = true
                } label: {
                    Text(editor.title.isEmpty ? L10n.text("knowledge.title.untitled") : editor.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .opacity(isEditingTitle ? 0 : 1)

                TextField(
                    L10n.text("knowledge.title.placeholder"),
                    text: $titleDraft,
                    onCommit: {
                        Task {
                            await editor.commitTitleResolvingCollisions(titleDraft)
                            isEditingTitle = false
                            titleFieldFocused = false
                        }
                    }
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: min(UIScreen.main.bounds.width * 0.42, 280))
                .focused($titleFieldFocused)
                .opacity(isEditingTitle ? 1 : 0)
            }
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                Task {
                    if editor.isEditMode {
                        _ = await editor.saveNow()
                        await libraryViewModel.refresh()
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        editor.isEditMode.toggle()
                    }
                }
            } label: {
                Text(editor.isEditMode ? L10n.text("knowledge.nav.save") : L10n.text("knowledge.nav.edit"))
                    .foregroundStyle(Color.accentColor)
            }
            .disabled(editor.isSaving)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
        }
    }

    private func loadTask() async {
        await editor.load()
        await libraryViewModel.refresh()
        titleDraft = editor.title
    }

    private var missingDocument: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(L10n.text("knowledge.not_found.title"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(L10n.text("knowledge.not_found.message"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - 网页 URL 内联条（Health `buttonActions` + `webInputSection`）

private struct KnowledgeWebInlineRow: View {
    @Binding var text: String
    var isBusy: Bool
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("knowledge.web.prompt"))
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 8) {
                TextField(L10n.text("knowledge.web.field_placeholder"), text: $text)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .disabled(isBusy)
                    .submitLabel(.send)
                    .onSubmit { onSubmit() }

                Button(action: onSubmit) {
                    Image(systemName: "arrowtriangle.up.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary)
                }
                .disabled(!canSubmit || isBusy)
            }
        }
    }

    private var canSubmit: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

// MARK: - View modifiers（拆分修饰链，减轻类型推断压力）

private struct HiddenScrollIndicatorsIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollIndicators(.hidden)
        } else {
            content
        }
    }
}

/// 仅 `fileImporter`；网页导入改为内联条，避免与 Health 交互分叉。
private struct FileImportOnlyModifier: ViewModifier {
    @Binding var showFileImporter: Bool
    let onFile: (URL) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .pdf, .text],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onFile(url)
            }
        }
    }
}

private struct ImageOCRModifier: ViewModifier {
    @Binding var showImageSourcePicker: Bool
    @Binding var showImagePicker: Bool
    @Binding var imagePickerSource: KnowledgeImagePicker.Source
    let onImage: (UIImage) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(L10n.text("knowledge.image_source.title"), isPresented: $showImageSourcePicker, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(L10n.text("knowledge.image_source.camera")) {
                        imagePickerSource = .camera
                        showImagePicker = true
                    }
                }
                Button(L10n.text("knowledge.image_source.library")) {
                    imagePickerSource = .photoLibrary
                    showImagePicker = true
                }
                Button(L10n.text("common.cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $showImagePicker) {
                KnowledgeImagePicker(
                    source: imagePickerSource,
                    onCancel: { showImagePicker = false },
                    onImagePicked: { image in
                        showImagePicker = false
                        onImage(image)
                    }
                )
            }
    }
}

private struct DeleteConfirmModifier: ViewModifier {
    @Binding var showDeleteConfirmation: Bool
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.alert(L10n.text("knowledge.delete.title"), isPresented: $showDeleteConfirmation) {
            Button(L10n.text("knowledge.delete.confirm"), role: .destructive, action: onDelete)
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("knowledge.delete.message"))
        }
    }
}

private struct EditorErrorAlertModifier: ViewModifier {
    @ObservedObject var editor: KnowledgeDocumentEditorViewModel

    func body(content: Content) -> some View {
        content.alert(L10n.text("knowledge.error.title"), isPresented: Binding(
            get: { editor.errorMessage != nil },
            set: { if $0 == false { editor.clearError() } }
        )) {
            Button(L10n.text("common.ok")) { editor.clearError() }
        } message: {
            Text(editor.errorMessage ?? "")
        }
    }
}
