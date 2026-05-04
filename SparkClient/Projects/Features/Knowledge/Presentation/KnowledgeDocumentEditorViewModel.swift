import Combine
import Foundation
import SwiftUI
import UIKit

/// 知识库文档编辑页 ViewModel
/// 负责：文档加载、编辑保存、防抖自动存、AI 润色/翻译/OCR、文件/网页导入、向量索引构建
@MainActor
final class KnowledgeDocumentEditorViewModel: ObservableObject {

    // MARK: - 外部传入
    let documentID: UUID  // 当前编辑的文档 ID

    // MARK: - UI 状态
    @Published var title: String = ""                     // 文档标题
    @Published var bodyText: String = ""                  // 文档正文
    @Published var isEditMode: Bool = true                // 是否处于编辑模式
    @Published private(set) var document: KnowledgeDocument?  // 文档领域模型
    @Published private(set) var isLoading = false         // 正在加载
    @Published private(set) var isSaving = false          // 正在保存
    @Published var errorMessage: String?                  // 错误提示
    @Published var embeddingModels: [AIScenarioRemoteModelRow] = []  // 可选的嵌入模型列表
    @Published var selectedEmbeddingModelName: String = ""  // 当前选中的嵌入模型
    @Published private(set) var embeddingInProgress = false  // 正在构建向量
    @Published private(set) var textProcessingInProgress = false  // 正在处理文本（AI/导入）

    // MARK: - 业务用例（UseCase）依赖
    private let loadListUseCase: LoadKnowledgeListUseCase
    private let loadDocumentUseCase: LoadKnowledgeDocumentUseCase
    private let updateDocumentUseCase: UpdateKnowledgeDocumentUseCase
    private let deleteDocumentUseCase: DeleteKnowledgeDocumentUseCase
    private let buildEmbeddingsUseCase: BuildKnowledgeEmbeddingsUseCase
    private let polishUseCase: PolishKnowledgeTextUseCase
    private let translateUseCase: TranslateKnowledgeTextUseCase
    private let ocrUseCase: OCRKnowledgeImageUseCase
    private let importFileUseCase: ImportKnowledgeFromFileUseCase
    private let importWebUseCase: ImportKnowledgeFromWebUseCase

    // MARK: - 工具依赖
    private let aiConfigCenter: AIConfigCenter
    private let logger: Logger

    // MARK: - 防抖保存任务
    private var saveDebounceTask: Task<Void, Never>?

    // MARK: - 初始化
    init(
        documentID: UUID,
        loadListUseCase: LoadKnowledgeListUseCase,
        loadDocumentUseCase: LoadKnowledgeDocumentUseCase,
        updateDocumentUseCase: UpdateKnowledgeDocumentUseCase,
        deleteDocumentUseCase: DeleteKnowledgeDocumentUseCase,
        buildEmbeddingsUseCase: BuildKnowledgeEmbeddingsUseCase,
        polishUseCase: PolishKnowledgeTextUseCase,
        translateUseCase: TranslateKnowledgeTextUseCase,
        ocrUseCase: OCRKnowledgeImageUseCase,
        importFileUseCase: ImportKnowledgeFromFileUseCase,
        importWebUseCase: ImportKnowledgeFromWebUseCase,
        aiConfigCenter: AIConfigCenter,
        logger: Logger = ConsoleLogger()
    ) {
        self.documentID = documentID
        self.loadListUseCase = loadListUseCase
        self.loadDocumentUseCase = loadDocumentUseCase
        self.updateDocumentUseCase = updateDocumentUseCase
        self.deleteDocumentUseCase = deleteDocumentUseCase
        self.buildEmbeddingsUseCase = buildEmbeddingsUseCase
        self.polishUseCase = polishUseCase
        self.translateUseCase = translateUseCase
        self.ocrUseCase = ocrUseCase
        self.importFileUseCase = importFileUseCase
        self.importWebUseCase = importWebUseCase
        self.aiConfigCenter = aiConfigCenter
        self.logger = logger
    }

    // MARK: - 统计信息
    /// 字符数
    var characterCount: Int {
        bodyText.count
    }

    /// 估算 Token 数（与写作页对齐）
    var tokenEstimate: Int {
        let wordCount = bodyText.split { $0.isWhitespace || $0.isPunctuation }.count
        return max(1, Int(ceil(Double(wordCount) * 1.2)))
    }

    // MARK: - 加载文档
    func load() async {
        isLoading = true
        defer { isLoading = false }
        saveDebounceTask?.cancel()
        do {
            // 刷新可用的嵌入模型
            await refreshEmbeddingModels()

            // 加载文档
            guard let doc = try await loadDocumentUseCase.execute(id: documentID) else {
                errorMessage = L10n.text("knowledge.error.document_missing")
                return
            }
            document = doc
            title = doc.title
            bodyText = doc.content
            saveDebounceTask?.cancel()

            // 空内容默认进入编辑模式
            isEditMode = doc.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 提交标题（自动解决重名）
    func commitTitleResolvingCollisions(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != title else { return }
        let unique = await resolveUniqueDocumentTitle(trimmed)
        title = unique
        _ = await save(silentEmpty: false)
    }

    /// 自动生成不重复标题：base → base_1 → base_2
    private func resolveUniqueDocumentTitle(_ baseName: String) async -> String {
        guard let docs = try? await loadListUseCase.execute(query: nil) else { return baseName }
        let others = docs.filter { $0.id != documentID }
        let conflicts = others.filter {
            $0.title == baseName || $0.title.hasPrefix("\(baseName)_")
        }
        guard !conflicts.isEmpty else { return baseName }

        var maxIndex = 0
        for doc in conflicts {
            let name = doc.title
            if name == baseName {
                maxIndex = max(maxIndex, 1)
            } else if name.hasPrefix("\(baseName)_") {
                let suffix = name.dropFirst(baseName.count + 1)
                if let num = Int(suffix) {
                    maxIndex = max(maxIndex, num + 1)
                }
            }
        }
        return maxIndex > 0 ? "\(baseName)_\(maxIndex)" : baseName
    }

    /// 刷新嵌入模型列表
    private func refreshEmbeddingModels() async {
        guard let bundles = try? await aiConfigCenter.effectiveScenarioBundles() else {
            embeddingModels = []
            selectedEmbeddingModelName = ""
            return
        }
        let bundle = bundles.embedding
        embeddingModels = bundle.models
        let preferred = selectedEmbeddingModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedEmbeddingModelName = bundle.resolveRow(
            preferredModelName: preferred.isEmpty ? nil : preferred
        )?.name ?? ""
    }

    // MARK: - 手动保存
    func saveNow() async -> Bool {
        await save(silentEmpty: false)
    }

    /// 防抖自动保存（1.2s 延迟）
    func scheduleDebouncedSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !Task.isCancelled else { return }
            _ = await self.save(silentEmpty: true)
        }
    }

    /// 保存文档
    private func save(silentEmpty: Bool) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedBody.isEmpty {
            if silentEmpty { return false }
            errorMessage = L10n.text("knowledge.error.body_empty")
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let draft = KnowledgeDocumentDraft(
                title: trimmedTitle.isEmpty ? "Untitled Document" : trimmedTitle,
                content: trimmedBody,
                scope: document?.scope ?? .personal,
                boundModelID: document?.boundModelID,
                source: document?.source ?? .user
            )
            let updated = try await updateDocumentUseCase.execute(id: documentID, draft: draft)
            document = updated
            title = updated.title
            bodyText = updated.content
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - 删除文档
    func deleteDocument() async -> Bool {
        do {
            try await deleteDocumentUseCase.execute(id: documentID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - AI 功能
    /// AI 润色
    func polish() async {
        await runTextAction { try await self.polishUseCase.execute(text: self.bodyText) }
    }

    /// AI 翻译
    func translate() async {
        await runTextAction { try await self.translateUseCase.execute(text: self.bodyText) }
    }

    /// 图片 OCR 文字提取
    func appendFromOCR(image: UIImage) async {
        textProcessingInProgress = true
        defer { textProcessingInProgress = false }
        do {
            let text = try await ocrUseCase.execute(image: image)
            let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { return }
            if bodyText.isEmpty {
                bodyText = piece
            } else {
                bodyText += "\n\n" + piece
            }
            scheduleDebouncedSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 文件导入（追加）
    func importFromFile(url: URL) async {
        textProcessingInProgress = true
        defer { textProcessingInProgress = false }
        do {
            let text = try await importFileUseCase.execute(fileURL: url)
            let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { return }
            if bodyText.isEmpty {
                bodyText = piece
            } else {
                bodyText += "\n\n" + piece
            }
            scheduleDebouncedSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 网页内容导入（支持多 URL）
    func appendWebContent(from raw: String) async {
        let parts = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }

        textProcessingInProgress = true
        defer { textProcessingInProgress = false }
        do {
            for urlString in parts {
                let text = try await importWebUseCase.execute(urlString: urlString)
                let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !piece.isEmpty else { continue }
                if bodyText.isEmpty {
                    bodyText = piece
                } else {
                    bodyText += "\n" + piece
                }
            }
            scheduleDebouncedSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 清空正文
    func clearBody() {
        bodyText = ""
        scheduleDebouncedSave()
    }

    // MARK: - 构建向量索引
    func buildEmbeddings() async {
        let model = selectedEmbeddingModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            errorMessage = L10n.text("knowledge.error.embedding_no_model")
            return
        }
        embeddingInProgress = true
        defer { embeddingInProgress = false }
        do {
            // 先保存
            guard await save(silentEmpty: false) else { return }
            // 构建向量
            let updated = try await buildEmbeddingsUseCase.execute(
                documentID: documentID,
                modelName: model
            )
            document = updated
            logger.info("知识向量索引完成 document=\(documentID) model=\(model)", module: .general)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 统一执行 AI 文本处理
    private func runTextAction(_ work: @escaping () async throws -> String) async {
        textProcessingInProgress = true
        defer { textProcessingInProgress = false }
        do {
            let next = try await work()
            let trimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            bodyText = trimmed
            scheduleDebouncedSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 清除错误
    func clearError() {
        errorMessage = nil
    }
}
