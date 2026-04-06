import Combine
import Foundation

/// 知识库列表/详情/搜索共用状态：只依赖用例，不直接访问 `Core Data`。
@MainActor
final class KnowledgeLibraryViewModel: ObservableObject {
    @Published private(set) var documents: [KnowledgeDocument] = []
    @Published private(set) var searchResults: [KnowledgeSearchResult] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let loadListUseCase: LoadKnowledgeListUseCase
    private let loadDocumentUseCase: LoadKnowledgeDocumentUseCase
    private let createUseCase: CreateKnowledgeDocumentUseCase
    private let updateUseCase: UpdateKnowledgeDocumentUseCase
    private let deleteUseCase: DeleteKnowledgeDocumentUseCase
    private let searchUseCase: SearchKnowledgeUseCase
    private let reindexUseCase: ReindexKnowledgeDocumentUseCase
    private var hasLoaded = false

    init(
        loadListUseCase: LoadKnowledgeListUseCase,
        loadDocumentUseCase: LoadKnowledgeDocumentUseCase,
        createUseCase: CreateKnowledgeDocumentUseCase,
        updateUseCase: UpdateKnowledgeDocumentUseCase,
        deleteUseCase: DeleteKnowledgeDocumentUseCase,
        searchUseCase: SearchKnowledgeUseCase,
        reindexUseCase: ReindexKnowledgeDocumentUseCase
    ) {
        self.loadListUseCase = loadListUseCase
        self.loadDocumentUseCase = loadDocumentUseCase
        self.createUseCase = createUseCase
        self.updateUseCase = updateUseCase
        self.deleteUseCase = deleteUseCase
        self.searchUseCase = searchUseCase
        self.reindexUseCase = reindexUseCase
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh(query: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await loadListUseCase.execute(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDocument(id: UUID) async -> KnowledgeDocument? {
        do {
            return try await loadDocumentUseCase.execute(id: id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// 新建空白知识文档并持久化（标题本地化「新知识」），用于列表「+」后直接进入 `KnowledgeDocumentDetailView` 编辑态。
    @discardableResult
    func createNewDocument() async -> KnowledgeDocument? {
        isLoading = true
        defer { isLoading = false }
        let draft = KnowledgeDocumentDraft(
            title: L10n.text("knowledge.new_document_title"),
            content: "",
            source: .user
        )
        do {
            let document = try await createUseCase.execute(draft)
            await refresh()
            return document
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func saveDocument(
        id: UUID?,
        title: String,
        content: String,
        source: KnowledgeDocumentSource = .user
    ) async -> KnowledgeDocument? {
        isLoading = true
        defer { isLoading = false }
        let draft = KnowledgeDocumentDraft(title: title, content: content, source: source)
        do {
            let document: KnowledgeDocument
            if let id {
                document = try await updateUseCase.execute(id: id, draft: draft)
            } else {
                document = try await createUseCase.execute(draft)
            }
            await refresh()
            return document
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteDocument(id: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await deleteUseCase.execute(id: id)
            documents.removeAll { $0.id == id }
            searchResults.removeAll { $0.documentID == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            searchResults = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            searchResults = try await searchUseCase.execute(query: trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rebuildIndex(for id: UUID) async {
        do {
            _ = try await reindexUseCase.execute(id: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
