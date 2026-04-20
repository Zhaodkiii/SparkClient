import SwiftUI

/// AI 设置中「模型偏好」子页：按向量 / 语音 / 优化等分区，配置各场景使用的模型（试用策略或本地目录 + 服务端下发的多模型列表）。
struct AIModelPreferencesView: View {
    /// 当前展示的设置分区。
    enum Focus {
        case embedding
        case voice
        case optimization
    }

    @Binding var snapshot: AISettingsSnapshot
    let focus: Focus

    /// 试用策略里某一场景下可选的一条模型（用于 Picker）。
    private struct TrialModelOption: Identifiable, Hashable {
        let id: String
        let name: String
        let displayName: String
        let company: String
    }

    /// 绑定到快照中的 `UserInfo`，供各分区 TextField / Picker 使用。
    private var userInfoBinding: Binding<UserInfo> {
        $snapshot.userInfo
    }

    /// 当前快照中的用户信息（只读便捷访问）。
    private var userInfo: UserInfo {
        snapshot.userInfo
    }

    /// 生成本地场景模型的双向绑定：同步「按场景选中的模型名」与 `UserInfo` 中对应字段。
    /// 读取顺序：显式选中 → `UserInfo` 存稿 → 本地 bundle 默认行。
    private func scenarioLocalModelBinding(
        scenario: AIScenario,
        userInfoKeyPath: WritableKeyPath<UserInfo, String>
    ) -> Binding<String> {
        Binding(
            get: {
                let snap = snapshot
                if let picked = snap.scenarioDefaultModels[scenario.rawValue], picked.isEmpty == false {
                    return picked
                }
                let fromUserInfo = snap.userInfo[keyPath: userInfoKeyPath]
                if fromUserInfo.isEmpty == false {
                    return fromUserInfo
                }
                if let row = snap.resolveScenarioRow(for: scenario) {
                    return row.model
                }
                return ""
            },
            set: { newValue in
                var next = snapshot
                if newValue.isEmpty {
                    next.scenarioDefaultModels.removeValue(forKey: scenario.rawValue)
                } else {
                    next.scenarioDefaultModels[scenario.rawValue] = newValue
                }
                next.userInfo[keyPath: userInfoKeyPath] = newValue
                snapshot = next
            }
        )
    }

    /// 展示名优先用本地模型目录里的 `displayName`，否则用服务端下发的模型 id 字符串。
    private func bundleRowDisplayName(_ row: AIScenarioRemoteModelRow) -> String {
        if let m = snapshot.allModels.first(where: { $0.name == row.model }) {
            return m.displayName
        }
        return row.model
    }

    /// 用于图标与展示：优先 bundle 行内的厂商字段，否则回退到目录中的 `company`。
    private func companyLabelForBundleRow(_ row: AIScenarioRemoteModelRow) -> String {
        if let c = row.providerCompany, c.isEmpty == false {
            return c
        }
        return snapshot.allModels.first(where: { $0.name == row.model })?.company ?? ""
    }

    /// 当前试用激活时，该 `AIScenario` 在 `trialModelPolicy` 中的可选条目（每场景可多行）。
    private func trialModelOptions(for scenario: AIScenario) -> [TrialModelOption] {
        guard snapshot.trial.isActive else { return [] }
        let items = snapshot.trialModelPolicy.filter { $0.scenario == scenario }
        return items.map { item in
            let name = item.config.model
            let model = snapshot.allModels.first(where: { $0.name == name })
            return TrialModelOption(
                id: "\(scenario.rawValue)|\(name)",
                name: name,
                displayName: model?.displayName ?? name,
                company: model?.company ?? "TRIAL"
            )
        }
    }

    /// 该场景在试用策略中是否至少有一条可选模型。
    private func hasTrialModels(for scenario: AIScenario) -> Bool {
        trialModelOptions(for: scenario).isEmpty == false
    }

    /// 本地 Key 路径下的「文本类优化」候选：目录模型 + 能力筛选 + 已配置非空 API Key（无 bundle 时的回退列表）。
    private var textOptimizationModels: [AllModels] {
        snapshot.allModels
            .filter {
                $0.identity == .model &&
                $0.company.uppercased() != LocalModelService.localCompany &&
                supportsTextOptimization($0) &&
                hasValidAPIKey(for: $0)
            }
            .sorted { $0.position < $1.position }
    }

    /// 视觉优化候选：要求多模态 + 本地 Key。
    private var visualOptimizationModels: [AllModels] {
        snapshot.allModels
            .filter {
                $0.identity == .model &&
                $0.company.uppercased() != LocalModelService.localCompany &&
                $0.supportsMultimodal &&
                hasValidAPIKey(for: $0)
            }
            .sorted { $0.position < $1.position }
    }

    /// Router 场景：与文本优化共用同一套目录回退列表。
    private var routerModels: [AllModels] {
        textOptimizationModels
    }

    /// 抽数场景：与文本优化共用同一套目录回退列表。
    private var extractionModels: [AllModels] {
        textOptimizationModels
    }

    /// 报告解读场景：与文本优化共用同一套目录回退列表。
    private var reportInterpretationModels: [AllModels] {
        textOptimizationModels
    }

    var body: some View {
        Form {
            switch focus {
            case .embedding:
                embeddingSection
            case .voice:
                voiceSection
            case .optimization:
                optimizationSections
            }
        }
        .navigationTitle(title)
        // `userInfo` 变更时表单控件过渡动画。
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snapshot.userInfo)
    }

    /// 向量嵌入：模型名仍为自由文本输入（不走优化场景的 bundle / 试用分流）。
    private var embeddingSection: some View {
        Section(L10n.text("ai_settings.row.embedding")) {
            TextField(
                L10n.text("ai_settings.field.embedding_model"),
                text: userInfoBinding.chooseEmbeddingModel
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
    }

    /// 语音合成：模型名自由文本（与优化 bundle 分流无关）。
    private var voiceSection: some View {
        Section(L10n.text("ai_settings.row.voice")) {
            TextField(
                L10n.text("ai_settings.field.voice_model"),
                text: userInfoBinding.textToSpeechModel
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
    }

    /// 各推理/优化场景：来源（试用 / 本地 Key）+ `modelPicker`；多模型以服务端 `scenarioRemoteBundles` 为准。
    private var optimizationSections: some View {
        Group {
            Section(header: Text(L10n.text("ai_settings.scenario.optimization_text"))) {
                headerExplain(
                    icon: "paintbrush.pointed",
                    message: L10n.text("ai_settings.prefs.explain.optimization_text")
                )

                sourcePicker(
                    selection: userInfoBinding.optimizationTextSource,
                    isTrialAvailable: hasTrialModels(for: .optimizationText)
                )

                modelPicker(
                    title: L10n.text("ai_settings.prefs.picker.optimization_text"),
                    scenario: .optimizationText,
                    selectedModelName: scenarioLocalModelBinding(
                        scenario: .optimizationText,
                        userInfoKeyPath: \.optimizationTextModel
                    ),
                    source: userInfo.optimizationTextSource,
                    localModels: textOptimizationModels
                )
            }

            Section(header: Text(L10n.text("ai_settings.scenario.optimization_visual"))) {
                headerExplain(
                    icon: "paintbrush",
                    message: L10n.text("ai_settings.prefs.explain.optimization_visual")
                )

                sourcePicker(
                    selection: userInfoBinding.optimizationVisualSource,
                    isTrialAvailable: hasTrialModels(for: .optimizationVisual)
                )

                modelPicker(
                    title: L10n.text("ai_settings.prefs.picker.optimization_visual"),
                    scenario: .optimizationVisual,
                    selectedModelName: scenarioLocalModelBinding(
                        scenario: .optimizationVisual,
                        userInfoKeyPath: \.optimizationVisualModel
                    ),
                    source: userInfo.optimizationVisualSource,
                    localModels: visualOptimizationModels
                )
            }

            Section(header: Text(L10n.text("ai_settings.scenario.context_folding"))) {
                headerExplain(
                    icon: "rectangle.compress.vertical",
                    message: L10n.text("ai_settings.prefs.explain.context_folding")
                )

                Toggle(L10n.text("ai_settings.prefs.toggle.context_folding"), isOn: userInfoBinding.useContextFolding)
                    .tint(.accentColor)

                if userInfo.useContextFolding {
                    sourcePicker(
                        selection: userInfoBinding.contextFoldingSource,
                        isTrialAvailable: hasTrialModels(for: .contextFolding)
                    )

                    modelPicker(
                        title: L10n.text("ai_settings.prefs.picker.context_folding"),
                        scenario: .contextFolding,
                        selectedModelName: scenarioLocalModelBinding(
                            scenario: .contextFolding,
                            userInfoKeyPath: \.contextFoldingModel
                        ),
                        source: userInfo.contextFoldingSource,
                        localModels: textOptimizationModels
                    )
                }
            }

            Section(header: Text(L10n.text("ai_settings.scenario.router"))) {
                headerExplain(
                    icon: "arrow.triangle.branch",
                    message: L10n.text("ai_settings.prefs.explain.router")
                )

                sourcePicker(
                    selection: userInfoBinding.routerSource,
                    isTrialAvailable: hasTrialModels(for: .router)
                )

                modelPicker(
                    title: L10n.text("ai_settings.scenario.router"),
                    scenario: .router,
                    selectedModelName: scenarioLocalModelBinding(scenario: .router, userInfoKeyPath: \.routerModel),
                    source: userInfo.routerSource,
                    localModels: routerModels
                )

                Stepper(
                    String(
                        format: L10n.text("ai_settings.prefs.max_tool_sets"),
                        locale: Locale.current,
                        userInfo.maxToolSets
                    ),
                    value: userInfoBinding.maxToolSets,
                    in: 1 ... 5
                )
            }

            Section(header: Text(L10n.text("ai_settings.prefs.section.extraction"))) {
                headerExplain(
                    icon: "cross.case",
                    message: L10n.text("ai_settings.prefs.explain.data_extraction")
                )

                sourcePicker(
                    selection: userInfoBinding.dataExtractionSource,
                    isTrialAvailable: hasTrialModels(for: .modelConfig)
                )

                modelPicker(
                    title: L10n.text("ai_settings.prefs.picker.data_extraction"),
                    scenario: .modelConfig,
                    selectedModelName: scenarioLocalModelBinding(
                        scenario: .modelConfig,
                        userInfoKeyPath: \.dataExtractionModel
                    ),
                    source: userInfo.dataExtractionSource,
                    localModels: extractionModels
                )
            }

            Section(header: Text(L10n.text("ai_settings.prefs.section.report_interpretation"))) {
                headerExplain(
                    icon: "doc.text.magnifyingglass",
                    message: L10n.text("ai_settings.prefs.explain.report_interpretation")
                )

                sourcePicker(
                    selection: userInfoBinding.reportInterpretationSource,
                    isTrialAvailable: hasTrialModels(for: .reportInterpretation)
                )

                modelPicker(
                    title: L10n.text("ai_settings.prefs.picker.report_interpretation"),
                    scenario: .reportInterpretation,
                    selectedModelName: scenarioLocalModelBinding(
                        scenario: .reportInterpretation,
                        userInfoKeyPath: \.reportInterpretationModel
                    ),
                    source: userInfo.reportInterpretationSource,
                    localModels: reportInterpretationModels
                )
            }
        }
    }

    /// 试用可用时展示「服务端试用 / 本地 Key」分段控件。
    private func sourcePicker(
        selection: Binding<AIModelSelectionSource>,
        isTrialAvailable: Bool
    ) -> some View {
        Group {
            if isTrialAvailable {
                Picker(L10n.text("ai_settings.prefs.source_config"), selection: selection) {
                    Text(L10n.text("ai_settings.prefs.source_trial")).tag(AIModelSelectionSource.trial)
                    Text(L10n.text("ai_settings.prefs.source_local_key")).tag(AIModelSelectionSource.localKey)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    /// 按场景选择模型：试用走 `trialModelPolicy`；本地优先用 bootstrap 下发的 `models[]`，否则回退到目录 + API Key 过滤列表。
    @ViewBuilder
    private func modelPicker(
        title: String,
        scenario: AIScenario,
        selectedModelName: Binding<String>,
        source: AIModelSelectionSource,
        localModels: [AllModels]
    ) -> some View {
        if source == .trial, hasTrialModels(for: scenario) {
            let options = trialModelOptions(for: scenario)
            Picker(title, selection: selectedModelName) {
                ForEach(options) { item in
                    Text(item.displayName).tag(item.name)
                }
            }

            if let selectedTrial = options.first(where: { $0.name == selectedModelName.wrappedValue }) {
                modelSummaryRow(
                    icon: iconForCompany(selectedTrial.company),
                    displayName: selectedTrial.displayName,
                    subtitle: selectedTrial.name
                )
            }
        } else {
            // 本地 Key：优先用运行时本地合成的场景 `models[]`（Pro 覆盖仅在内存，设置页仅编辑本地目录）。
            let bundle = snapshot.localScenarioBundles().bundle(for: scenario)
            if bundle.models.isEmpty == false {
                Picker(title, selection: selectedModelName) {
                    ForEach(bundle.models, id: \.model) { row in
                        Text(bundleRowDisplayName(row)).tag(row.model)
                    }
                }

                let pickedName = selectedModelName.wrappedValue
                if let row = bundle.models.first(where: { $0.model == pickedName }) {
                    modelSummaryRow(
                        icon: iconForCompany(companyLabelForBundleRow(row)),
                        displayName: bundleRowDisplayName(row),
                        subtitle: row.model
                    )
                }
            } else if localModels.isEmpty {
                Text(L10n.text("ai_settings.no_models_configure_key"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker(title, selection: selectedModelName) {
                    ForEach(localModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }

                if let selectedLocal = localModels.first(where: { $0.name == selectedModelName.wrappedValue }) {
                    modelSummaryRow(
                        icon: iconForCompany(selectedLocal.company),
                        displayName: selectedLocal.displayName,
                        subtitle: selectedLocal.name
                    )
                }
            }
        }
    }

    /// 分区顶部说明（图标 + 灰色说明文案）。
    private func headerExplain(icon: String, message: String) -> some View {
        VStack(alignment: .center) {
            Image(systemName: icon)
                .font(.largeTitle)
//                .fontWeight(.bold)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .padding()

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Picker 下方展示当前选中模型的摘要行。
    private func modelSummaryRow(icon: String, displayName: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// 文本优化场景下，用于筛选「有能力做文本侧优化」的目录模型。
    private func supportsTextOptimization(_ model: AllModels) -> Bool {
        model.supportsReasoning || model.supportsToolUse || model.supportsSearch || model.supportsMultimodal
    }

    /// 本地 Key 路径：该厂商在快照中是否已有非空、非隐藏的 API Key（用于目录回退列表）。
    private func hasValidAPIKey(for model: AllModels) -> Bool {
        let company = model.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard company.isEmpty == false else { return false }
        return snapshot.apiKeys.contains { key in
            key.company.uppercased() == company &&
            key.isHidden == false &&
            key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    /// 按厂商缩写选用 SF Symbol，用于摘要行左侧图标。
    private func iconForCompany(_ company: String) -> String {
        switch company.uppercased() {
        case "OPENAI":
            return "circle.hexagongrid.fill"
        case "ANTHROPIC":
            return "triangle.fill"
        case "GOOGLE", "GEMINI":
            return "sparkles"
        case "DEEPSEEK":
            return "wave.3.forward.circle.fill"
        case "SPARK":
            return "bolt.horizontal.circle.fill"
        default:
            return "building.2.crop.circle"
        }
    }

    /// 导航栏标题（本地化 key）。
    private var title: String {
        switch focus {
        case .embedding:
            return L10n.text("ai_settings.row.embedding")
        case .voice:
            return L10n.text("ai_settings.row.voice")
        case .optimization:
            return L10n.text("ai_settings.row.optimization")
        }
    }
}

/// SwiftUI 预览用容器：持有可变 `AISettingsSnapshot`，嵌入 `NavigationView`。
@MainActor
private struct AIModelPreferencesViewPreviewHost: View {
    @State private var snapshot = AISettingsSnapshot.default

    var body: some View {
        NavigationView {
            AIModelPreferencesView(
                snapshot: $snapshot,
                focus: .optimization
            )
        }
    }
}

@MainActor
struct AIModelPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AIModelPreferencesViewPreviewHost()
                .preferredColorScheme(.light)

            AIModelPreferencesViewPreviewHost()
                .preferredColorScheme(.dark)
        }
    }
}
