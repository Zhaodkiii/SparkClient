import SwiftUI

/// AI 设置「模型」子页：对齐 Health `ModelsView` — 试用区 + 单一主列表（`unifiedModels`）、菜单添加在线/本地/智能体、高级子页、行内编辑 Sheet。

/// 供编辑 Sheet 绑定的可识别模型 ID。
private struct ModelIDBox: Identifiable {
    let id: UUID
}

struct ModelsSettingsView: View {
    @Binding var models: [AllModels]
    @ObservedObject var viewModel: AISettingsViewModel

    @State private var searchText = ""
    @State private var selectedIdentity: ModelsSettingsIdentityFilter = .all
    @State private var isEditing = false

    @State private var showAddOnline = false
    @State private var showLocalDownload = false
    @State private var showAgentSheet = false
    @State private var editingAgent: AllModels?
    @State private var editingModelForSheet: ModelIDBox?

    @State private var inlineError: String?
    @State private var modelPendingDelete: AllModels?
    @State private var showDeleteConfirm = false
    @State private var showToggleKeyError = false

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 与 Health 一致：未隐藏且 `company` 非空的密钥，按大写厂商参与可见性（与 Key 行一致）。
    private var visibleProviderCompanies: Set<String> {
        Set(
            viewModel.snapshot.apiKeys
                .filter {
                    $0.isHidden == false &&
                    $0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
                .map { $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
        )
    }

    /// 供智能体表单选择基座：已安装的本地 GGUF 模型。
    private var localBaseModelsForAgent: [AllModels] {
        models
            .filter { $0.isLocalModel }
            .sorted { $0.position < $1.position }
    }

    /// 主列表：身份 + API Key 可见性 + 仅 `displayName` 搜索（含拼音），按 `position` 排序。
    private var unifiedModels: [AllModels] {
        models
            .filter(matchesIdentity)
            .filter(matchesApiKeyVisibility)
            .filter(matchesSearchUnified)
            .sorted { $0.position < $1.position }
    }

    private var searchPrompt: String {
        selectedIdentity == .agent
            ? L10n.text("ai_settings.models.search.agents")
            : L10n.text("ai_settings.models.search.models")
    }

    /// 与 Health 一致：`all` / `model` 下标题均为「模型」，仅 `agent` 分段为智能体标题。
    private var titleText: String {
        selectedIdentity == .agent
            ? L10n.text("ai_settings.models.nav_title.agents")
            : L10n.text("ai_settings.models.nav_title.models")
    }

    var body: some View {
        VStack {
            List {
                trialChatModelsSection
                mainModelsSection
            }
        }
        .navigationTitle(titleText)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 75)
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isEditing.toggle() }) {
                    Image(systemName: isEditing ? "checkmark.circle" : "line.3.horizontal")
                }
            }

            ToolbarItem(placement: .principal) {
                if !isEditing {
                    Picker("", selection: $selectedIdentity) {
                        ForEach(ModelsSettingsIdentityFilter.allCases, id: \.self) { filter in
                            Text(filter.localizedTitle).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                if isEditing {
                    Button {
                        resetModelPositionToDefault()
                    } label: {
                        Label(L10n.text("ai_settings.toolbar.reset_sort"), systemImage: "arrow.up.arrow.down")
                    }
                } else {
                    Menu {
                        Button {
                            showAddOnline = true
                        } label: {
                            Label(L10n.text("ai_settings.models.menu.add_online_model"), systemImage: "cloud")
                        }

                        Button {
                            showLocalDownload = true
                        } label: {
                            Label(L10n.text("ai_settings.models.menu.add_local_model"), systemImage: "externaldrive")
                        }

                        Button {
                            editingAgent = nil
                            showAgentSheet = true
                        } label: {
                            Label(L10n.text("ai_settings.models.menu.add_agent"), systemImage: "person.crop.circle.badge.plus")
                        }

                        NavigationLink {
                            ModelsAdvancedEditorView(
                                models: $models,
                                selectedIdentity: $selectedIdentity,
                                searchText: $searchText
                            )
                        } label: {
                            Label(L10n.text("ai_settings.models.menu.advanced"), systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .onAppear {
            initializeModelStates()
        }
        .sheet(isPresented: $showAddOnline) {
            AddOnlineModelSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showLocalDownload) {
            LocalModelDownloadSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showAgentSheet) {
            NavigationView {
                ModelsSettingsAgentSheet(
                    localBaseModels: localBaseModelsForAgent,
                    editingAgent: editingAgent,
                    onCreate: { displayName, iconSymbol, baseModelName, systemPrompt in
                        viewModel.createLocalAgent(
                            displayName: displayName,
                            iconSymbol: iconSymbol,
                            baseModelName: baseModelName,
                            systemPrompt: systemPrompt
                        )
                    },
                    onUpdate: { id, displayName, iconSymbol, baseModelName, systemPrompt in
                        viewModel.updateLocalAgent(
                            id: id,
                            displayName: displayName,
                            iconSymbol: iconSymbol,
                            baseModelName: baseModelName,
                            systemPrompt: systemPrompt
                        )
                    }
                )
            }
            .onDisappear {
                editingAgent = nil
            }
        }
        .sheet(item: $editingModelForSheet) { box in
            EditSparkModelSheet(viewModel: viewModel, modelID: box.id)
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { inlineError != nil },
            set: { presented in
                if presented == false {
                    inlineError = nil
                }
            }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(inlineError ?? "")
        }
        .alert(L10n.text("ai_settings.models.alert.delete_confirm_title"), isPresented: $showDeleteConfirm, presenting: modelPendingDelete) { model in
            Button(L10n.text("common.cancel"), role: .cancel) {
                modelPendingDelete = nil
            }
            Button(L10n.text("ai_settings.models.action.delete"), role: .destructive) {
                performDelete(model)
                modelPendingDelete = nil
            }
        } message: { model in
            Text(String(format: L10n.text("ai_settings.models.alert.delete_confirm_message"), model.displayName))
        }
        .alert(L10n.text("ai_settings.models.alert.need_api_key_title"), isPresented: $showToggleKeyError) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(L10n.text("ai_settings.models.alert.need_api_key_message"))
        }
        .task {
            await viewModel.refreshTrialStatus()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var trialChatModelsSection: some View {
        if viewModel.snapshot.trial.isActive {
            let names = viewModel.snapshot.chatTrialPolicyModelNames()
            if names.isEmpty == false {
                Section {
                    Text(L10n.text("ai_settings.models.trial.explain"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(names, id: \.self) { name in
                        trialChatModelToggleRow(modelName: name)
                    }
                } header: {
                    Text(L10n.text("ai_settings.models.section.trial_models"))
                }
            }
        }
    }

    private func trialChatModelToggleRow(modelName: String) -> some View {
        let display = viewModel.snapshot.allModels.first(where: { $0.name == modelName })?.displayName ?? modelName
        let company = viewModel.snapshot.allModels.first(where: { $0.name == modelName })?.company ?? ""
        let disabled = viewModel.snapshot.trialChatPickerDisabledModelNames.contains(modelName)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: ModelsSettingsRowChrome.iconSystemName(for: company))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .font(.title3)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(display)
                    .font(.headline)
                Text(L10n.text("ai_settings.models.trial.badge"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !disabled },
                set: { on in
                    viewModel.setTrialChatPickerDisabled(modelName: modelName, disabled: !on)
                }
            ))
            .labelsHidden()
            .tint(.blue)
        }
        .padding(.vertical, 4)
    }

    private var mainModelsSection: some View {
        Section {
            if unifiedModels.isEmpty {
                Text(
                    normalizedSearch.isEmpty
                        ? L10n.text("ai_settings.models.empty.list_none")
                        : L10n.text("ai_settings.models.empty.advanced_no_match")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                ForEach(unifiedModels) { model in
                    if let binding = bindingForModel(id: model.id) {
                        ModelsSettingsMainRow(
                            model: model,
                            isEditing: isEditing,
                            priceLabel: ModelsSettingsRowChrome.priceTierLabel(model.priceTier),
                            priceColor: ModelsSettingsRowChrome.priceTierColor(model.priceTier),
                            hasValidAPIKey: hasValidAPIKey(for: model),
                            onInfo: { handleEdit(model) },
                            onDelete: { requestDelete(model) },
                            onToggleInvalid: { showToggleKeyError = true },
                            visible: Binding(
                                get: { binding.wrappedValue.isHidden == false },
                                set: { visible in
                                    binding.wrappedValue.isHidden = !visible
                                }
                            )
                        )
                    }
                }
                .onMove(perform: moveUnifiedModels)
            }
        }
    }

    // MARK: - Filtering & keys

    private func matchesIdentity(_ model: AllModels) -> Bool {
        switch selectedIdentity {
        case .all:
            return true
        case .model:
            return model.identity == .model
        case .agent:
            return model.identity == .agent
        }
    }

    /// 与 Health `filteredModels`：非智能体且非本地目录行时，厂商须在可见密钥集合中。
    private func matchesApiKeyVisibility(_ model: AllModels) -> Bool {
        if model.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == LocalModelService.localCompany.uppercased() {
            return true
        }
        let c = model.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard c.isEmpty == false else { return false }
        return visibleProviderCompanies.contains(c)
    }

    /// 有搜索词时仅匹配非空 `displayName`（原文 + 拼音）。
    private func matchesSearchUnified(_ model: AllModels) -> Bool {
        guard normalizedSearch.isEmpty == false else { return true }
        let dn = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dn.isEmpty == false else { return false }
        if dn.lowercased().contains(normalizedSearch) { return true }
        return dn.toPinyinForSearch().lowercased().contains(normalizedSearch)
    }

    private func bindingForModel(id: UUID) -> Binding<AllModels>? {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return nil }
        return $models[index]
    }

    /// 本地模型无需厂商 Key；否则需存在未隐藏且非空的对应厂商密钥。
    private func hasValidAPIKey(for model: AllModels) -> Bool {
        let company = model.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let localCo = LocalModelService.localCompany.uppercased()
        if company == localCo {
            return true
        }
        guard company.isEmpty == false else { return false }
        return viewModel.snapshot.apiKeys.contains { key in
            key.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == company &&
            key.isHidden == false &&
            key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    /// 首次进入：无有效 Key 的云端模型自动隐藏（对齐 Health `initializeModelStates`）。
    private func initializeModelStates() {
        for i in models.indices {
            if hasValidAPIKey(for: models[i]) == false && models[i].isHidden == false {
                models[i].isHidden = true
            }
        }
    }

    private func handleEdit(_ model: AllModels) {
        if model.isLocalAgent {
            editingAgent = model
            showAgentSheet = true
        } else {
            editingModelForSheet = ModelIDBox(id: model.id)
        }
    }

    private func requestDelete(_ model: AllModels) {
        modelPendingDelete = model
        showDeleteConfirm = true
    }

    private func performDelete(_ model: AllModels) {
        if model.source == .system {
            inlineError = L10n.text("ai_settings.models.alert.cannot_delete_system")
            return
        }
        if model.isLocalModel {
            Task {
                do {
                    try await viewModel.removeLocalModel(model)
                } catch {
                    inlineError = error.localizedDescription
                }
            }
        } else {
            models.removeAll { $0.id == model.id }
        }
    }

    /// 与 Health `moveModel`：列表索引为模型 `position`；智能体为 `index + 1000`。
    private func moveUnifiedModels(from source: IndexSet, to destination: Int) {
        var reordered = unifiedModels
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, model) in reordered.enumerated() {
            var positionIndex = index
            if model.identity == .agent {
                positionIndex = index + 1000
            }
            guard let modelIndex = models.firstIndex(where: { $0.id == model.id }) else { continue }
            models[modelIndex].position = positionIndex
        }
    }

    private func resetModelPositionToDefault() {
        let sortedByName = models.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        for (index, model) in sortedByName.enumerated() {
            guard let modelIndex = models.firstIndex(where: { $0.id == model.id }) else { continue }
            models[modelIndex].position = model.identity == .agent ? index + 1000 : index
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// SwiftUI 预览：独立 `UserDefaults` suite + 内存密钥仓，嵌入 `NavigationView` 以展示导航栏与工具栏。
@MainActor
private struct ModelsSettingsPreviewHost: View {
    @StateObject private var viewModel: AISettingsViewModel

    init() {
        let repository = DefaultAISettingsRepository(
            userDefaults: UserDefaults(suiteName: "ModelsSettingsView.preview") ?? .standard,
            secretStore: InMemoryAISettingsSecretStore()
        )
        let vm = AISettingsViewModel(
            loadUseCase: LoadAISettingsUseCase(repository: repository),
            saveUseCase: SaveAISettingsUseCase(repository: repository)
        )
        vm.snapshot = .default
        vm.snapshot.allModels = Self.sampleModels
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        NavigationView {
            ModelsSettingsView(
                models: Binding(
                    get: { viewModel.snapshot.allModels },
                    set: { viewModel.snapshot.allModels = $0 }
                ),
                viewModel: viewModel
            )
        }
    }

    private static var sampleModels: [AllModels] {
        [
            AllModels(
                name: "local-qwen25-15b",
                displayName: "Qwen2.5 1.5B",
                identity: .model,
                position: 1,
                company: LocalModelService.localCompany,
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                iconSymbol: "cpu",
                baseModelName: nil,
                localFilename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
                systemPrompt: nil,
                source: .custom,
                timestamp: Date()
            ),
            AllModels(
                name: "local-agent-demo",
                displayName: "健康问答助手",
                identity: .agent,
                position: 1000,
                company: LocalModelService.localCompany,
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                iconSymbol: "heart.text.square",
                baseModelName: "local-qwen25-15b",
                localFilename: nil,
                systemPrompt: "你是一个专业且友好的健康问答助手。",
                source: .custom,
                timestamp: Date()
            )
        ]
    }
}

@MainActor
struct ModelsSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ModelsSettingsPreviewHost()
                .preferredColorScheme(.light)

            ModelsSettingsPreviewHost()
                .preferredColorScheme(.dark)
        }
    }
}
