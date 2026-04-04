import SwiftUI

struct AIModelPreferencesView: View {
    enum Focus {
        case embedding
        case voice
        case optimization
    }

    @Binding var snapshot: AISettingsSnapshot
    let focus: Focus

    private struct TrialModelOption: Identifiable, Hashable {
        let id: String
        let name: String
        let displayName: String
        let company: String
    }

    private var userInfoBinding: Binding<UserInfo> {
        $snapshot.userInfo
    }

    private var userInfo: UserInfo {
        snapshot.userInfo
    }

    private var trialModelNames: [String] {
        guard snapshot.trial.isActive else { return [] }
        let names = snapshot.trialModelPolicy.map { $0.config.model }.filter { $0.isEmpty == false }
        return Array(Set(names)).sorted()
    }

    private var hasTrialModels: Bool {
        trialModelNames.isEmpty == false
    }

    private var trialModelOptions: [TrialModelOption] {
        trialModelNames.map { name in
            let model = snapshot.allModels.first(where: { $0.name == name })
            return TrialModelOption(
                id: name,
                name: name,
                displayName: model?.displayName ?? name,
                company: model?.company ?? "TRIAL"
            )
        }
    }

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

    private var routerModels: [AllModels] {
        textOptimizationModels
    }

    private var extractionModels: [AllModels] {
        textOptimizationModels
    }

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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snapshot.userInfo)
    }

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

    private var optimizationSections: some View {
        Group {
            Section(header: Text("文本优化模型")) {
                headerExplain(
                    icon: "paintbrush.pointed",
                    message: "文本优化模型用于提示词优化、搜索问题改写、知识检索改写与内容优化。"
                )

                sourcePicker(
                    selection: userInfoBinding.optimizationTextSource,
                    isTrialAvailable: hasTrialModels
                )

                modelPicker(
                    title: "选择文本优化模型",
                    selectedModelName: userInfoBinding.optimizationTextModel,
                    source: userInfo.optimizationTextSource,
                    localModels: textOptimizationModels
                )
            }

            Section(header: Text("视觉优化模型")) {
                headerExplain(
                    icon: "paintbrush",
                    message: "视觉优化模型用于图像理解、多模态改写与 OCR 相关能力。"
                )

                sourcePicker(
                    selection: userInfoBinding.optimizationVisualSource,
                    isTrialAvailable: hasTrialModels
                )

                modelPicker(
                    title: "选择视觉优化模型",
                    selectedModelName: userInfoBinding.optimizationVisualModel,
                    source: userInfo.optimizationVisualSource,
                    localModels: visualOptimizationModels
                )
            }

            Section(header: Text("上下文折叠")) {
                headerExplain(
                    icon: "rectangle.compress.vertical",
                    message: "当对话过长时自动压缩旧上下文，减少 token 消耗并提升响应速度。"
                )

                Toggle("启用上下文折叠", isOn: userInfoBinding.useContextFolding)
                    .tint(.accentColor)

                if userInfo.useContextFolding {
                    sourcePicker(
                        selection: userInfoBinding.contextFoldingSource,
                        isTrialAvailable: hasTrialModels
                    )

                    modelPicker(
                        title: "上下文折叠模型",
                        selectedModelName: userInfoBinding.contextFoldingModel,
                        source: userInfo.contextFoldingSource,
                        localModels: textOptimizationModels
                    )
                }
            }

            Section(header: Text("Router 模型")) {
                headerExplain(
                    icon: "arrow.triangle.branch",
                    message: "Router 模型用于在对话前判断需要调用的工具组。"
                )

                sourcePicker(
                    selection: userInfoBinding.routerSource,
                    isTrialAvailable: hasTrialModels
                )

                modelPicker(
                    title: "Router 模型",
                    selectedModelName: userInfoBinding.routerModel,
                    source: userInfo.routerSource,
                    localModels: routerModels
                )

                Stepper(
                    "最大工具组数: \(userInfo.maxToolSets)",
                    value: userInfoBinding.maxToolSets,
                    in: 1 ... 5
                )
            }

            Section(header: Text("抽数模型配置")) {
                headerExplain(
                    icon: "cross.case",
                    message: "抽数模型用于结构化医疗信息抽取与字段规整。"
                )

                sourcePicker(
                    selection: userInfoBinding.dataExtractionSource,
                    isTrialAvailable: hasTrialModels
                )

                modelPicker(
                    title: "抽数模型",
                    selectedModelName: userInfoBinding.dataExtractionModel,
                    source: userInfo.dataExtractionSource,
                    localModels: extractionModels
                )
            }

            Section(header: Text("报告解读模型配置")) {
                headerExplain(
                    icon: "doc.text.magnifyingglass",
                    message: "报告解读模型用于体检/检验报告分析与建议生成。"
                )

                sourcePicker(
                    selection: userInfoBinding.reportInterpretationSource,
                    isTrialAvailable: hasTrialModels
                )

                modelPicker(
                    title: "报告解读模型",
                    selectedModelName: userInfoBinding.reportInterpretationModel,
                    source: userInfo.reportInterpretationSource,
                    localModels: reportInterpretationModels
                )
            }
        }
    }

    private func sourcePicker(
        selection: Binding<AIModelSelectionSource>,
        isTrialAvailable: Bool
    ) -> some View {
        Group {
            if isTrialAvailable {
                Picker("配置来源", selection: selection) {
                    Text("服务端试用").tag(AIModelSelectionSource.trial)
                    Text("本地 Key").tag(AIModelSelectionSource.localKey)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private func modelPicker(
        title: String,
        selectedModelName: Binding<String>,
        source: AIModelSelectionSource,
        localModels: [AllModels]
    ) -> some View {
        if source == .trial, hasTrialModels {
            Picker(title, selection: selectedModelName) {
                ForEach(trialModelOptions) { item in
                    Text(item.displayName).tag(item.name)
                }
            }

            if let selectedTrial = trialModelOptions.first(where: { $0.name == selectedModelName.wrappedValue }) {
                modelSummaryRow(
                    icon: iconForCompany(selectedTrial.company),
                    displayName: selectedTrial.displayName,
                    subtitle: selectedTrial.name
                )
            }
        } else {
            if localModels.isEmpty {
                Text("暂无可用模型，请先在模型密钥中配置有效 API Key。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker(title, selection: selectedModelName) {
                    ForEach(localModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
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

    private func supportsTextOptimization(_ model: AllModels) -> Bool {
        model.supportsReasoning || model.supportsToolUse || model.supportsSearch || model.supportsMultimodal
    }

    private func hasValidAPIKey(for model: AllModels) -> Bool {
        let company = model.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard company.isEmpty == false else { return false }
        return snapshot.apiKeys.contains { key in
            key.company.uppercased() == company &&
            key.isHidden == false &&
            key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

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
