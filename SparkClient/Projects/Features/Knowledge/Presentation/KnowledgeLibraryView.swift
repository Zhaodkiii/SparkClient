import SwiftUI

/// 知识库首页：文档列表、下拉刷新、跳转详情与搜索。
/// 新建：与 `AI_HLY/KnowledgeListView` 一致——插入空白文档后 **push** 到 `KnowledgeDocumentDetailView`（编辑态由详情页根据空正文决定）。
struct KnowledgeLibraryView: View {
    let dependencies: KnowledgeFeatureDependencies
    @ObservedObject var viewModel: KnowledgeLibraryViewModel
    /// 编程式导航目标（`NavigationLink(isActive:)`，兼容 `NavigationView` + iOS 15）。
    @State private var pendingDetailDocumentID: UUID?

    var body: some View {
        ZStack {
            List {
                if viewModel.documents.isEmpty, viewModel.isLoading == false {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.documents) { document in
                        NavigationLink {
                            KnowledgeDocumentDetailView(dependencies: dependencies, viewModel: viewModel, documentID: document.id)
                                .hidesMainTabBarWhenPushed()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(document.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(document.listSubtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack(spacing: 12) {
                                    Text(document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    Text("\(document.chunkCount) chunks")
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteDocument(id: document.id)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(L10n.text("knowledge.library.title"))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink {
                        KnowledgeSearchView(dependencies: dependencies, viewModel: viewModel)
                            .hidesMainTabBarWhenPushed()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }

                    Button {
                        Task { await createDocumentAndNavigate() }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert(L10n.text("knowledge.error.title"), isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { newValue in
                    if newValue == false {
                        viewModel.clearError()
                    }
                }
            )) {
                Button(L10n.text("common.ok")) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }

            // 隐藏链接触发 push，避免单独 Sheet 编辑页。
            NavigationLink(
                destination: Group {
                    if let id = pendingDetailDocumentID {
                        KnowledgeDocumentDetailView(dependencies: dependencies, viewModel: viewModel, documentID: id)
                            .hidesMainTabBarWhenPushed()
                    }
                },
                isActive: Binding(
                    get: { pendingDetailDocumentID != nil },
                    set: { active in
                        if active == false {
                            pendingDetailDocumentID = nil
                        }
                    }
                )
            ) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .hidden()
        }
    }

    /// 与 `KnowledgeListView.addNewKnowledge` 一致：先持久化再导航到写作页。
    private func createDocumentAndNavigate() async {
        guard let doc = await viewModel.createNewDocument() else { return }
        pendingDetailDocumentID = doc.id
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(L10n.text("knowledge.library.empty.title"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(L10n.text("knowledge.library.empty.subtitle"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.text("knowledge.library.empty.action")) {
                Task { await createDocumentAndNavigate() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 48)
    }
}
