import SwiftUI
import UniformTypeIdentifiers

private enum IdentityFilter: String, CaseIterable {
    case all = "全部"
    case model = "模型"
    case agent = "智能体"
}

struct ModelsSettingsView: View {
    @Binding var models: [AllModels]
    @ObservedObject var viewModel: AISettingsViewModel

    @State private var searchText = ""
    @State private var selectedIdentity: IdentityFilter = .all
    @State private var isEditing = false

    @State private var importingLocalModel = false
    @State private var showAgentCreator = false
    @State private var busyCatalogItemID: String?
    @State private var busyLocalModelID: UUID?
    @State private var inlineError: String?

    private var catalog: [LocalModelCatalogItem] {
        viewModel.localModelCatalog()
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredCatalog: [LocalModelCatalogItem] {
        guard normalizedSearch.isEmpty == false else { return catalog }
        return catalog.filter { item in
            item.displayName.lowercased().contains(normalizedSearch) ||
            item.summary.lowercased().contains(normalizedSearch)
        }
    }

    private var localBaseModels: [AllModels] {
        models
            .filter { $0.isLocalModel }
            .filter(matchesSearch)
            .sorted { $0.position < $1.position }
    }

    private var localAgents: [AllModels] {
        models
            .filter { $0.isLocalAgent }
            .filter(matchesSearch)
            .sorted { $0.position < $1.position }
    }

    private var filteredAdvancedModelIDs: [UUID] {
        models
            .filter(matchesIdentity)
            .filter(matchesSearch)
            .sorted { $0.position < $1.position }
            .map(\.id)
    }

    private var searchPrompt: String {
        selectedIdentity == .agent ? "搜索智能体" : "搜索模型"
    }

    private var titleText: String {
        selectedIdentity == .agent ? "智能体" : "模型"
    }

    var body: some View {
        NavigationView {
            VStack {
                List {
                    if selectedIdentity != .agent {
                        localModelCatalogSection
                        localModelInstalledSection
                    }

                    if selectedIdentity != .model {
                        localAgentSection
                    }

                    allModelEditorSection
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
                            ForEach(IdentityFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
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
                            Label("恢复默认排序", systemImage: "arrow.up.arrow.down")
                        }
                    } else {
                        Menu {
                            Button {
                                addModel()
                            } label: {
                                Label("新增自定义模型", systemImage: "plus.square.on.square")
                            }

                            Button {
                                importingLocalModel = true
                            } label: {
                                Label("添加本地模型", systemImage: "externaldrive")
                            }

                            Button {
                                showAgentCreator = true
                            } label: {
                                Label("添加新智能体", systemImage: "person.crop.circle.badge.plus")
                            }
                            .disabled(models.contains(where: { $0.isLocalModel }) == false)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
            .fileImporter(
                isPresented: $importingLocalModel,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        do {
                            try await viewModel.importLocalModel(from: url)
                        } catch {
                            inlineError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    inlineError = error.localizedDescription
                }
            }
            .sheet(isPresented: $showAgentCreator) {
                NavigationView {
                    LocalAgentBuilderSheet(
                        localBaseModels: localBaseModels,
                        onCreate: { displayName, iconSymbol, baseModelName, systemPrompt in
                            viewModel.createLocalAgent(
                                displayName: displayName,
                                iconSymbol: iconSymbol,
                                baseModelName: baseModelName,
                                systemPrompt: systemPrompt
                            )
                            showAgentCreator = false
                        }
                    )
                }
            }
            .alert("操作失败", isPresented: Binding(
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
        }
    }

    private var localModelCatalogSection: some View {
        Section("本地模型下载") {
            if filteredCatalog.isEmpty {
                Text("没有匹配的可下载模型")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredCatalog) { item in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName)
                                .font(.headline)
                            Text(item.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                busyCatalogItemID = item.id
                                defer { busyCatalogItemID = nil }
                                do {
                                    try await viewModel.installLocalModel(item: item)
                                } catch {
                                    inlineError = error.localizedDescription
                                }
                            }
                        } label: {
                            if busyCatalogItemID == item.id {
                                ProgressView()
                            } else {
                                Text("下载")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busyCatalogItemID != nil)
                    }
                }
            }

            Button {
                importingLocalModel = true
            } label: {
                Label("导入本地 .gguf 文件", systemImage: "square.and.arrow.down")
            }
        }
    }

    private var localModelInstalledSection: some View {
        Section("已安装本地模型") {
            if localBaseModels.isEmpty {
                Text(normalizedSearch.isEmpty ? "暂无本地模型，请先下载或导入。" : "没有匹配的本地模型")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(localBaseModels) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        BaseModelCard(model: model)
                        HStack(spacing: 10) {
                            Button("用于对话") {
                                viewModel.setChatModel(model)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("删除") {
                                Task {
                                    busyLocalModelID = model.id
                                    defer { busyLocalModelID = nil }
                                    do {
                                        try await viewModel.removeLocalModel(model)
                                    } catch {
                                        inlineError = error.localizedDescription
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(busyLocalModelID == model.id)
                        }
                    }
                }
            }
        }
    }

    private var localAgentSection: some View {
        Section("本地智能体") {
            Button {
                showAgentCreator = true
            } label: {
                Label("创建本地智能体", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(models.contains(where: { $0.isLocalModel }) == false)

            if localAgents.isEmpty {
                Text(normalizedSearch.isEmpty ? "暂无本地智能体。" : "没有匹配的智能体")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(localAgents) { agent in
                    HStack(spacing: 10) {
                        Image(systemName: agent.iconSymbol ?? "person.crop.circle")
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agent.displayName)
                            if let base = agent.baseModelName, base.isEmpty == false {
                                Text("基座：\(base)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("用于对话") {
                            viewModel.setChatModel(agent)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .onDelete(perform: deleteLocalAgent)
            }
        }
    }

    private var allModelEditorSection: some View {
        Section("全部模型（高级）") {
            if filteredAdvancedModelIDs.isEmpty {
                Text("没有匹配的模型记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredAdvancedModelIDs, id: \.self) { id in
                    if let modelBinding = bindingForModel(id: id) {
                        DisclosureGroup {
                            TextField(L10n.text("ai_settings.field.display_name"), text: modelBinding.displayName)
                            TextField(L10n.text("ai_settings.model"), text: modelBinding.name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField(L10n.text("ai_settings.field.company"), text: modelBinding.company)
                            Picker(L10n.text("ai_settings.field.identity"), selection: modelBinding.identity) {
                                ForEach(AIModelIdentity.allCases, id: \.self) { identity in
                                    Text(identity.rawValue).tag(identity)
                                }
                            }
                            Toggle(L10n.text("ai_settings.field.visible"), isOn: Binding(
                                get: { modelBinding.wrappedValue.isHidden == false },
                                set: { modelBinding.wrappedValue.isHidden = !$0 }
                            ))
                            Toggle(L10n.text("ai_settings.field.supports_search"), isOn: modelBinding.supportsSearch)
                            Toggle(L10n.text("ai_settings.field.supports_multimodal"), isOn: modelBinding.supportsMultimodal)
                            Toggle(L10n.text("ai_settings.field.supports_reasoning"), isOn: modelBinding.supportsReasoning)
                            Toggle("思考可控", isOn: modelBinding.reasoningControllable)
                            Picker("价格档位", selection: modelBinding.priceTier) {
                                Text("免费").tag(0)
                                Text("经济").tag(1)
                                Text("标准").tag(2)
                                Text("高级").tag(3)
                            }
                            Toggle("文本", isOn: modelBinding.supportsText)
                            Toggle(L10n.text("ai_settings.field.supports_tool_use"), isOn: modelBinding.supportsToolUse)
                        } label: {
                            Text(modelBinding.wrappedValue.displayName.isEmpty ? L10n.text("ai_settings.model_item") : modelBinding.wrappedValue.displayName)
                        }
                    }
                }
                .onDelete(perform: deleteAdvancedModels)
                .onMove(perform: moveAdvancedModels)
            }
        }
    }

    private func bindingForModel(id: UUID) -> Binding<AllModels>? {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return nil }
        return $models[index]
    }

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

    private func matchesSearch(_ model: AllModels) -> Bool {
        guard normalizedSearch.isEmpty == false else { return true }
        let searchable = [
            model.displayName,
            model.name,
            model.company,
            model.baseModelName ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        return searchable.contains(normalizedSearch)
    }

    private func addModel() {
        models.append(
            AllModels(
                name: "",
                displayName: "",
                identity: .model,
                position: (models.map(\.position).max() ?? 0) + 1,
                company: "",
                isHidden: false,
                supportsSearch: false,
                supportsMultimodal: false,
                supportsReasoning: false,
                supportsToolUse: false,
                supportsVoiceGen: false,
                supportsImageGen: false,
                source: .custom,
                timestamp: Date()
            )
        )
    }

    private func moveAdvancedModels(from source: IndexSet, to destination: Int) {
        var ids = filteredAdvancedModelIDs
        ids.move(fromOffsets: source, toOffset: destination)
        for (index, id) in ids.enumerated() {
            guard let modelIndex = models.firstIndex(where: { $0.id == id }) else { continue }
            models[modelIndex].position = index
        }
    }

    private func resetModelPositionToDefault() {
        let sortedByName = models.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        for (index, model) in sortedByName.enumerated() {
            guard let modelIndex = models.firstIndex(where: { $0.id == model.id }) else { continue }
            models[modelIndex].position = index
        }
    }

    private func deleteAdvancedModels(at offsets: IndexSet) {
        let removingIDs = offsets.compactMap { filteredAdvancedModelIDs[safe: $0] }
        models.removeAll { removingIDs.contains($0.id) }
    }

    private func deleteLocalAgent(at offsets: IndexSet) {
        let removingIDs = offsets.compactMap { localAgents[safe: $0]?.id }
        models.removeAll { removingIDs.contains($0.id) }
    }
}

private struct BaseModelCard: View {
    let model: AllModels

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.displayName)
                .font(.headline)
            Text(model.name)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                capabilityChip("推理", enabled: model.supportsReasoning)
                capabilityChip("工具", enabled: model.supportsToolUse)
                capabilityChip("多模态", enabled: model.supportsMultimodal)
            }
        }
        .padding(.vertical, 4)
    }

    private func capabilityChip(_ title: String, enabled: Bool) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(enabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct LocalAgentBuilderSheet: View {
    let localBaseModels: [AllModels]
    let onCreate: (String, String, String, String) -> Void

    @State private var displayName = ""
    @State private var iconSymbol = "stethoscope"
    @State private var selectedBaseModelName = ""
    @State private var systemPrompt = ""
    @Environment(\.dismiss) private var dismiss

    private let iconCandidates = [
        "stethoscope",
        "heart.text.square",
        "cross.case",
        "brain.head.profile",
        "person.text.rectangle",
        "waveform.path.ecg",
        "bandage",
        "bolt.heart",
        "leaf",
        "cpu",
        "person.badge.shield.checkmark",
        "sparkles"
    ]

    var body: some View {
        List {
            Section("基础信息") {
                TextField("智能体名称", text: $displayName)
                Picker("基座模型", selection: $selectedBaseModelName) {
                    ForEach(localBaseModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                if let selectedModel = localBaseModels.first(where: { $0.name == selectedBaseModelName }) {
                    BaseModelCard(model: selectedModel)
                }
            }

            Section("图标选择") {
                LazyVGrid(columns: [.init(.adaptive(minimum: 42))], spacing: 10) {
                    ForEach(iconCandidates, id: \.self) { icon in
                        Button {
                            iconSymbol = icon
                        } label: {
                            Image(systemName: icon)
                                .frame(width: 34, height: 34)
                                .padding(6)
                                .background(iconSymbol == icon ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("系统提示词（可选）") {
                TextEditor(text: $systemPrompt)
                    .frame(minHeight: 96)
            }
        }
        .navigationTitle("新建本地智能体")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") {
                    onCreate(displayName, iconSymbol, selectedBaseModelName, systemPrompt)
                }
                .disabled(canCreate == false)
            }
        }
        .onAppear {
            if selectedBaseModelName.isEmpty, let first = localBaseModels.first {
                selectedBaseModelName = first.name
            }
        }
    }

    private var canCreate: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        selectedBaseModelName.isEmpty == false
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

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
        ModelsSettingsView(
            models: Binding(
                get: { viewModel.snapshot.allModels },
                set: { viewModel.snapshot.allModels = $0 }
            ),
            viewModel: viewModel
        )
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
                position: 2,
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
