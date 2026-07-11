import SwiftUI

/// 知识库全文检索页：与 `SearchKnowledgeUseCase` 共用仓库检索逻辑。
struct KnowledgeSearchView: View {
    let dependencies: KnowledgeFeatureDependencies
    @ObservedObject var viewModel: KnowledgeLibraryViewModel
    @State private var query = ""

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                placeholder(
                    title: "Search the knowledge base",
                    systemImage: "magnifyingglass",
                    message: "Search across document titles, markdown body, and local chunks."
                )
                .listRowSeparator(.hidden)
            } else if viewModel.searchResults.isEmpty, viewModel.isLoading == false {
                placeholder(
                    title: "No matching documents",
                    systemImage: "doc.text.magnifyingglass",
                    message: "Try another term or open a document and add more detail."
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.searchResults) { result in
                    MainNavigationLink {
                        KnowledgeDocumentDetailView(dependencies: dependencies, viewModel: viewModel, documentID: result.documentID)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.title)
                                .font(.headline)
                            Text(result.excerpt)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Text("Score \(result.score, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search knowledge")
        .task(id: query.trimmingCharacters(in: .whitespacesAndNewlines)) {
            try? await Task.sleep(for: .milliseconds(250))
            guard Task.isCancelled == false else { return }
            await viewModel.search(query: query)
        }
    }

    private func placeholder(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 48)
    }
}
