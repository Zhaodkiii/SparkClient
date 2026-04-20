import Combine
import Foundation
import SwiftUI
import UIKit

/// 单篇知识「写作页」状态：编辑/预览、防抖保存、工具栏与向量化（仅依赖用例与 AI 设置快照）。
@MainActor
final class KnowledgeDocumentEditorViewModel: ObservableObject {
    let documentID: UUID

    @Published var title: String = ""
    @Published var bodyText: String = ""
    @Published var isEditMode: Bool = true
    @Published private(set) var document: KnowledgeDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var embeddingModels: [AllModels] = []
    @Published var selectedEmbeddingModelName: String = ""
    @Published private(set) var embeddingInProgress = false
    @Published private(set) var textProcessingInProgress = false

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
    private let aiConfigCenter: AIConfigCenter
    private let logger: Logger

    private var saveDebounceTask: Task<Void, Never>?

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

    var characterCount: Int {
        bodyText.count
    }

    /// 与 Health `KnowledgeWritingView.estimateTokens` 对齐：按词块 ×1.2 估算，仅供底部栏展示。
    var tokenEstimate: Int {
        let wordCount = bodyText.split { $0.isWhitespace || $0.isPunctuation }.count
        return max(1, Int(ceil(Double(wordCount) * 1.2)))
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = await aiConfigCenter.currentSnapshot()
            refreshEmbeddingModels(from: snapshot)

            guard let doc = try await loadDocumentUseCase.execute(id: documentID) else {
                errorMessage = L10n.text("knowledge.error.document_missing")
                return
            }
            document = doc
            title = doc.title
            bodyText = doc.content
            // 空正文进入编辑态，与 Health `KnowledgeWritingView.onAppear` 一致。
            isEditMode = doc.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 标题提交时按 Health 规则解决同名冲突（`base`、`base_1`…），再持久化。
    func commitTitleResolvingCollisions(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != title else { return }
        let unique = await resolveUniqueDocumentTitle(trimmed)
        title = unique
        _ = await save(silentEmpty: false)
    }

    private func resolveUniqueDocumentTitle(_ baseName: String) async -> String {
        guard let docs = try? await loadListUseCase.execute(query: nil) else { return baseName }
        let others = docs.filter { $0.id != documentID }
        let conflicts = others.filter { doc in
            doc.title == baseName || doc.title.hasPrefix("\(baseName)_")
        }
        guard conflicts.isEmpty == false else { return baseName }

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

    private func refreshEmbeddingModels(from snapshot: AISettingsSnapshot) {
        embeddingModels = KnowledgeEmbeddingResolution.visibleEmbeddingModels(in: snapshot)
        let preferred = snapshot.userInfo.chooseEmbeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = embeddingModels.first(where: { $0.name == preferred }) {
            selectedEmbeddingModelName = match.name
        } else if let first = embeddingModels.first {
            selectedEmbeddingModelName = first.name
        } else {
            selectedEmbeddingModelName = preferred
        }
    }

    /// 手动保存（导航栏「保存」）。
    func saveNow() async -> Bool {
        await save(silentEmpty: false)
    }

    /// 防抖自动保存：正文或标题变更后延迟写入。
    func scheduleDebouncedSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, Task.isCancelled == false else { return }
            _ = await self.save(silentEmpty: true)
        }
    }

    /// - Parameter silentEmpty: 防抖保存时若正文为空则静默跳过，不提示错误。
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

    func deleteDocument() async -> Bool {
        do {
            try await deleteDocumentUseCase.execute(id: documentID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func polish() async {
        await runTextAction { try await self.polishUseCase.execute(text: self.bodyText) }
    }

    func translate() async {
        await runTextAction { try await self.translateUseCase.execute(text: self.bodyText) }
    }

    func appendFromOCR(image: UIImage) async {
        textProcessingInProgress = true
        defer { textProcessingInProgress = false }
        do {
            let text = try await ocrUseCase.execute(image: image)
            let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard piece.isEmpty == false else { return }
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

    /// 导入文件并 **追加** 到正文（对齐 Health `processDocument`）。
    func importFromFile(url: URL) async {
        textProcessingInProgress = true
        defer { textProcessingInProgress = false }
        do {
            let text = try await importFileUseCase.execute(fileURL: url)
            let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard piece.isEmpty == false else { return }
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

    /// 支持多 URL（空格/换行分隔），依次抓取并 **追加**（对齐 Health `processWeb`）。
    func appendWebContent(from raw: String) async {
        let parts = raw
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard parts.isEmpty == false else { return }

        textProcessingInProgress = true
        defer { textProcessingInProgress = false }
        do {
            for urlString in parts {
                let text = try await importWebUseCase.execute(urlString: urlString)
                let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard piece.isEmpty == false else { continue }
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

    func clearBody() {
        bodyText = ""
        scheduleDebouncedSave()
    }

    func buildEmbeddings() async {
        let model = selectedEmbeddingModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.isEmpty == false else {
            errorMessage = L10n.text("knowledge.error.embedding_no_model")
            return
        }
        embeddingInProgress = true
        defer { embeddingInProgress = false }
        do {
            if await save(silentEmpty: false) == false { return }
            let updated = try await buildEmbeddingsUseCase.execute(documentID: documentID, modelName: model)
            document = updated
            logger.info("知识向量索引完成 document=\(documentID) model=\(model)", module: .general)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runTextAction(_ work: @escaping () async throws -> String) async {
        textProcessingInProgress = true
        defer { textProcessingInProgress = false }
        do {
            let next = try await work()
            let trimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return }
            bodyText = trimmed
            scheduleDebouncedSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
