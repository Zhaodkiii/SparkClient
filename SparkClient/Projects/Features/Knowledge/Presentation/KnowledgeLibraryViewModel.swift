import Combine
import Foundation
/// 知识库列表页 ViewModel
/// 负责：文档列表加载、搜索、增删改查、索引重建、状态管理
@MainActor
final class KnowledgeLibraryViewModel: ObservableObject {

    // MARK: - UI 状态
    /// 文档列表数据
    @Published private(set) var documents: [KnowledgeDocument] = []
    /// 搜索结果数据
    @Published private(set) var searchResults: [KnowledgeSearchResult] = []
    /// 加载中状态
    @Published private(set) var isLoading = false
    /// 错误提示信息
    @Published var errorMessage: String?

    // MARK: - 业务用例（UseCase）依赖
    private let loadListUseCase: LoadKnowledgeListUseCase
    private let loadDocumentUseCase: LoadKnowledgeDocumentUseCase
    private let createUseCase: CreateKnowledgeDocumentUseCase
    private let updateUseCase: UpdateKnowledgeDocumentUseCase
    private let deleteUseCase: DeleteKnowledgeDocumentUseCase
    private let searchUseCase: SearchKnowledgeUseCase
    private let reindexUseCase: ReindexKnowledgeDocumentUseCase
    /// 知识同步编排；下拉刷新触发 Push+Pull，不阻塞首屏本地读取。
    private let knowledgeSyncSupervisor: KnowledgeSyncSupervisor?

    /// 是否已经加载过数据（避免重复加载）
    private var hasLoaded = false

    // MARK: - 初始化
    init(
        loadListUseCase: LoadKnowledgeListUseCase,
        loadDocumentUseCase: LoadKnowledgeDocumentUseCase,
        createUseCase: CreateKnowledgeDocumentUseCase,
        updateUseCase: UpdateKnowledgeDocumentUseCase,
        deleteUseCase: DeleteKnowledgeDocumentUseCase,
        searchUseCase: SearchKnowledgeUseCase,
        reindexUseCase: ReindexKnowledgeDocumentUseCase,
        knowledgeSyncSupervisor: KnowledgeSyncSupervisor? = nil
    ) {
        self.loadListUseCase = loadListUseCase
        self.loadDocumentUseCase = loadDocumentUseCase
        self.createUseCase = createUseCase
        self.updateUseCase = updateUseCase
        self.deleteUseCase = deleteUseCase
        self.searchUseCase = searchUseCase
        self.reindexUseCase = reindexUseCase
        self.knowledgeSyncSupervisor = knowledgeSyncSupervisor
    }

    // MARK: - 数据加载
    /// 页面显示时：只在首次进入加载数据
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    /// 刷新文档列表（支持搜索关键词）；只读本地 Core Data，不触发网络请求。
    func refresh(query: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await loadListUseCase.execute(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 下拉刷新：先返回本地列表（避免整页 loading），再异步触发 Push+Pull，完成后局部刷新。
    /// 同步失败不弹全局错误，只影响列表卡片的同步状态标识（工单 5.9、11.6）。
    func syncAndRefresh() async {
        await refresh()
        guard let knowledgeSyncSupervisor else { return }
        _ = await knowledgeSyncSupervisor.manualRefresh()
        await refresh()
    }

    /// 根据 ID 加载单个文档
    func loadDocument(id: UUID) async -> KnowledgeDocument? {
        do {
            return try await loadDocumentUseCase.execute(id: id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - 新建文档
    /// 创建空白新文档（点击 + 号使用）
    @discardableResult
    func createNewDocument() async -> KnowledgeDocument? {
        isLoading = true
        defer { isLoading = false }

        // 新建空白草稿，标题使用本地化「新知识」
        let draft = KnowledgeDocumentDraft(
            title: L10n.text("knowledge.new_document_title"),
            content: "",
            source: .user
        )

        do {
            let document = try await createUseCase.execute(draft)
            // 刷新列表
            await refresh()
            return document
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - 保存文档（新建 / 更新）
    /// 保存文档：有 ID 则更新，无 ID 则新建
    @discardableResult
    func saveDocument(
        id: UUID?,
        title: String,
        content: String,
        source: KnowledgeDocumentSource = .user
    ) async -> KnowledgeDocument? {
        isLoading = true
        defer { isLoading = false }

        let draft = KnowledgeDocumentDraft(
            title: title,
            content: content,
            source: source
        )

        do {
            let document: KnowledgeDocument
            if let id {
                // 有 ID → 更新
                document = try await updateUseCase.execute(id: id, draft: draft)
            } else {
                // 无 ID → 新建
                document = try await createUseCase.execute(draft)
            }
            await refresh()
            return document
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - 删除文档
    func deleteDocument(id: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await deleteUseCase.execute(id: id)
            // 同步删除列表与搜索结果中的数据
            documents.removeAll { $0.id == id }
            searchResults.removeAll { $0.documentID == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 搜索
    /// 执行关键词 + 语义搜索
    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
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

    // MARK: - 重建索引
    /// 重建文档文本切块与向量索引（清空旧向量）
    func rebuildIndex(for id: UUID) async {
        do {
            _ = try await reindexUseCase.execute(id: id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 列表卡片同步标识点击重试（`failedRetryable`）：只触发账号级后台重试，不进入阻断页面，卡片主体仍可正常打开。
    func retrySyncBadgeTapped() async {
        await syncAndRefresh()
    }

    // MARK: - 工具方法
    /// 清除错误信息
    func clearError() {
        errorMessage = nil
    }

    /// 切换账号/会话时重置状态
    func resetForSessionSwitch() {
        hasLoaded = false
        documents = []
        searchResults = []
        isLoading = false
        errorMessage = nil
    }
}
