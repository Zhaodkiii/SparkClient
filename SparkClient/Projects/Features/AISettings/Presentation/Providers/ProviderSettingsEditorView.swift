import SwiftUI

private enum ProviderSettingsSheet: Identifiable {
    case editModel(id: UUID)
    case manageModels

    var id: String {
        switch self {
        case .editModel(let id):
            return "editModel:\(id.uuidString)"
        case .manageModels:
            return "manageModels"
        }
    }
}

struct ProviderSettingsEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State var provider: APIKeys
    let viewModel: AISettingsViewModel
    let onDeleteModel: (UUID) -> Void
    let onToggleModelVisibility: (UUID, Bool) -> Void
    let hasValidAPIKeyForModel: (AllModels) -> Bool
    let onSave: (APIKeys) -> Void
    let onTest: (APIKeys) async -> Bool

    @State private var isTesting = false
    @State private var testPassed: Bool?
    @State private var showToggleKeyError = false
    @State private var showDeleteModelAlert = false
    @State private var pendingDeleteModelID: UUID?
    @State private var presentedSheet: ProviderSettingsSheet?

    private var providerModels: [AllModels] {
        let company = provider.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return viewModel.snapshot.allModels
            .filter { $0.identity == .model }
            .filter { $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == company }
            .sorted { $0.position < $1.position }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("厂商")
                    Spacer()
                    Text(provider.displayName)
                        .foregroundStyle(.secondary)
                }
                TextField("请求地址", text: $provider.requestURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("API Key", text: $provider.key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if provider.source == .custom {
                Section("自定义供应商") {
                    TextField("供应商名称", text: $provider.name)
                }
            }

            Section {
                if providerModels.isEmpty {
                    Text("该厂商暂未配置在线模型")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(providerModels) { model in
                        ModelsSettingsMainRow(
                            model: model,
                            isEditing: false,
                            priceLabel: ModelsSettingsRowChrome.priceTierLabel(model.priceTier),
                            priceColor: ModelsSettingsRowChrome.priceTierColor(model.priceTier),
                            hasValidAPIKey: hasValidAPIKeyForModel(model),
                            onInfo: { presentedSheet = .editModel(id: model.id) },
                            onDelete: {
                                pendingDeleteModelID = model.id
                                showDeleteModelAlert = true
                            },
                            onToggleInvalid: { showToggleKeyError = true },
                            visible: Binding(
                                get: { model.isHidden == false },
                                set: { visible in
                                    onToggleModelVisibility(model.id, visible)
                                }
                            )
                        )
                    }
                }
            } header: {
                HStack {
                    Text("该厂商模型")
                    Spacer()
                    Button {
                        presentedSheet = .manageModels
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }

            if provider.privacyPolicyURL.isEmpty == false {
                Section("隐私政策") {
                    if let url = URL(string: provider.privacyPolicyURL) {
                        Link("查看隐私政策", destination: url)
                            .font(.footnote)
                    }
                    Toggle(isOn: $provider.privacyPolicyAccepted) {
                        Text("我已阅读并同意该厂商隐私政策")
                            .font(.footnote)
                    }
                    .tint(.accentColor)
                }
            }

            Section {
                Button {
                    Task {
                        isTesting = true
                        defer { isTesting = false }
                        testPassed = await onTest(provider)
                    }
                } label: {
                    HStack {
                        Text("测试 API")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        } else if let passed = testPassed {
                            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(passed ? .green : .red)
                        }
                    }
                }
            }
        }
        .navigationTitle("编辑密钥")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    if provider.privacyPolicyURL.isEmpty == false, provider.privacyPolicyAccepted == false {
                        return
                    }
                    provider.privacyPolicyAcceptedAt = provider.privacyPolicyAccepted ? Date() : nil
                    onSave(provider)
                    dismiss()
                }
                .disabled(provider.privacyPolicyURL.isEmpty == false && provider.privacyPolicyAccepted == false)
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .editModel(let id):
                EditSparkModelSheet(viewModel: viewModel, modelID: id)
                    .onDisappear {
                        Task { await viewModel.persistSnapshotNow() }
                    }
            case .manageModels:
                ModelManagementView(provider: provider, viewModel: viewModel)
            }
        }
        .alert("删除模型？", isPresented: $showDeleteModelAlert) {
            Button("取消", role: .cancel) {
                pendingDeleteModelID = nil
            }
            Button("删除", role: .destructive) {
                guard let id = pendingDeleteModelID else { return }
                onDeleteModel(id)
                pendingDeleteModelID = nil
            }
        } message: {
            Text("删除后将从当前厂商模型列表移除。")
        }
        .alert("提示", isPresented: $showToggleKeyError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("请先配置有效 API Key")
        }
    }
}

extension APIKeys {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false { return trimmed }
        return company
    }
}
