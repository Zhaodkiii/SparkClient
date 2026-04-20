import SwiftUI

private enum ModelManagementSheet: Identifiable {
    case manualAdd

    var id: String { "manualAdd" }
}

struct ModelManagementView: View {
    let provider: APIKeys
    @ObservedObject var viewModel: AISettingsViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var remoteModels: [ProviderRemoteModel] = []
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var presentedSheet: ModelManagementSheet?

    private var companyModels: [AllModels] {
        let company = provider.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return viewModel.snapshot.allModels
            .filter { $0.identity == .model }
            .filter { $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == company }
            .sorted { $0.position < $1.position }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredCompanyModels: [AllModels] {
        guard normalizedSearchText.isEmpty == false else { return companyModels }
        return companyModels.filter { model in
            let values = [
                model.displayName,
                model.name,
                model.briefDescription,
            ]
            return values.contains {
                $0.lowercased().contains(normalizedSearchText)
            }
        }
    }

    private var filteredRemoteModels: [ProviderRemoteModel] {
        guard normalizedSearchText.isEmpty == false else { return remoteModels }
        return remoteModels.filter { model in
            [model.displayName, model.name, model.ownedBy].contains {
                $0.lowercased().contains(normalizedSearchText)
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                providerStatusSection
                addedModelsSection
                availableModelsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(provider.displayName) 模型")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索模型")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        presentedSheet = .manualAdd
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        Task { await refreshModels() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .refreshable {
                await refreshModels()
            }
            .task {
                if remoteModels.isEmpty {
                    await refreshModels()
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .manualAdd:
                AddOnlineModelSheet(viewModel: viewModel, initialCompany: provider.company)
            }
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { presented in
                if presented == false {
                    errorMessage = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var providerStatusSection: some View {
        Section("自动刷新") {
            if provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("当前厂商还没有可用的 API Key，暂时无法自动刷新远端模型列表。你仍然可以点右上角 + 手动添加模型。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("进入页面会自动拉取一次模型列表，也支持下拉或右上角按钮手动刷新。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var addedModelsSection: some View {
        Section {
            if filteredCompanyModels.isEmpty {
                Text(normalizedSearchText.isEmpty ? "该厂商还没有已添加模型" : "没有匹配的已添加模型")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(filteredCompanyModels.enumerated()), id: \.element.id) { _, model in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .font(.body)
                            Text(model.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.isHidden ? "已隐藏" : "已启用")
                            .font(.caption)
                            .foregroundColor(model.isHidden ? .secondary : .green)
                        if model.source != .system {
                            Button("删除", role: .destructive) {
                                deleteModel(model)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        } header: {
            Text("已添加 (\(filteredCompanyModels.count))")
        }
    }

    @ViewBuilder
    private var availableModelsSection: some View {
        Section {
            if provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyView()
            } else if isRefreshing && remoteModels.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("正在刷新模型列表...")
                    Spacer()
                }
            } else if filteredRemoteModels.isEmpty {
                Text(normalizedSearchText.isEmpty ? "暂未获取到可用模型" : "没有匹配的远端模型")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(filteredRemoteModels.enumerated()), id: \.element.id) { _, model in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .font(.body)
                            Text(model.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if model.ownedBy.isEmpty == false {
                                Text(model.ownedBy)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isModelAdded(model) {
                            Label("已添加", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                addModel(model)
                            } label: {
                                Label("添加", systemImage: "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("远端可用 (\(filteredRemoteModels.count))")
        } footer: {
            Text("自动刷新优先按厂商官方接口返回结果展示；如果接口不支持列出模型，仍可手动添加。")
        }
    }

    private func refreshModels() async {
        guard provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            remoteModels = try await viewModel.fetchRemoteModels(for: provider)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isModelAdded(_ remoteModel: ProviderRemoteModel) -> Bool {
        let remoteName = normalizedModelName(remoteModel.name)
        return companyModels.contains {
            normalizedModelName($0.name) == remoteName
        }
    }

    private func addModel(_ remoteModel: ProviderRemoteModel) {
        _ = viewModel.appendOrRevealRemoteModel(remoteModel, provider: provider)
        Task { await viewModel.persistSnapshotNow() }
    }

    private func deleteModel(_ model: AllModels) {
        guard model.source != .system else { return }
        viewModel.deleteOnlineModel(id: model.id)
        Task { await viewModel.persistSnapshotNow() }
    }

    private func normalizedModelName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "models/", with: "")
            .lowercased()
    }
}
