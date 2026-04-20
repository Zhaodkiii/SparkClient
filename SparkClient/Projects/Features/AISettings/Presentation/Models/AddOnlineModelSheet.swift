import SwiftUI

struct AddOnlineModelDraft: Sendable {
    var name: String
    var displayName: String
    var company: String
    var priceTier: Int
    var isHidden: Bool
    var supportsText: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var reasoningControllable: Bool
    var supportsToolUse: Bool
    var supportsImageGen: Bool
    var aiScenarios: [String]
    var aiToolScenarios: [String]
}

/// 对齐 Health `AddOnlineModelView`：表单添加云端模型（无 SwiftData）。
struct AddOnlineModelSheet: View {
    @ObservedObject var viewModel: AISettingsViewModel
    @Environment(\.dismiss) private var dismiss
    let initialCompany: String?
    let initialDraft: AddOnlineModelDraft?

    @State private var name = ""
    @State private var displayName = ""
    @State private var priceTier = 0
    @State private var isHidden = false
    @State private var supportsText = true
    @State private var supportsMultimodal = false
    @State private var supportsReasoning = false
    @State private var reasoningControllable = false
    @State private var supportsToolUse = false
    @State private var supportsImageGen = false
    @State private var selectedCompany = ""
    @State private var selectedScenarioRawValues: Set<String> = []
    @State private var selectedToolNames: Set<String> = Set(SparkToolName.all)
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showProbeSheet = false
    @State private var probeItems: [ModelCapabilityProbeProgressItem] = ModelCapabilityProbeStep.allCases.map {
        ModelCapabilityProbeProgressItem(step: $0, status: .pending, message: nil)
    }
    @State private var isProbing = false

    private let probeService = ClientModelCapabilityProbeService()

    init(
        viewModel: AISettingsViewModel,
        initialCompany: String? = nil,
        initialDraft: AddOnlineModelDraft? = nil
    ) {
        self.viewModel = viewModel
        self.initialCompany = initialCompany
        self.initialDraft = initialDraft
    }

    private var apiKeyRows: [APIKeys] {
        viewModel.snapshot.apiKeys.filter {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != LocalModelService.localCompany.uppercased()
        }
    }

    private var selectedCompanyDisplayName: String {
        guard let provider = selectedProviderForProbe else {
            return L10n.text("ai_settings.models.online.field.vendor")
        }
        return provider.localizedDisplayName
    }

    private var normalizedInitialCompany: String? {
        initialCompany?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private var isInitialCompanyAvailable: Bool {
        guard let normalizedInitialCompany else { return false }
        return apiKeyRows.contains {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedInitialCompany
        }
    }

    private var isCompanyLocked: Bool {
        isInitialCompanyAvailable
    }

    var body: some View {
        NavigationView {
            Form {

                Section(L10n.text("ai_settings.models.online.section.basic")) {
                    formInputRow(
                        icon: "rectangle.and.text.magnifyingglass", //  API 名称 / 标识 图标
                        title: L10n.text("ai_settings.models.online.field.api_name"),
                        prompt: L10n.text("ai_settings.models.online.field.api_name_prompt"),
                        text: $name
                    )
                    formInputRow(
                        icon: "textformat", // 显示名称 / 标题 图标
                        title: L10n.text("ai_settings.models.online.field.display_name"),
                        prompt: L10n.text("ai_settings.models.online.field.display_name_prompt"),
                        text: $displayName
                    )
                    formMenuRow(icon: "building.2", title: L10n.text("ai_settings.models.online.field.vendor")) {
                        Picker("", selection: $selectedCompany) {
                            ForEach(apiKeyRows, id: \.id) { key in
                                Text(key.localizedDisplayName)
                                    .tag(key.company)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isCompanyLocked)
                    } label: {
                        Text(selectedCompanyDisplayName)
                            .foregroundStyle(selectedProviderForProbe == nil ? .secondary : .primary)
                    }
                }
                Section(L10n.text("ai_settings.models.online.section.price")) {
                    formMenuRow(icon: "yensign", title: L10n.text("ai_settings.field.price_tier")) {
                        Picker("", selection: $priceTier) {
                            Text(L10n.text("ai_settings.field.price_tier.free")).tag(0)
                            Text(L10n.text("ai_settings.field.price_tier.economy")).tag(1)
                            Text(L10n.text("ai_settings.field.price_tier.standard")).tag(2)
                            Text(L10n.text("ai_settings.field.price_tier.premium")).tag(3)
                        }
                        .pickerStyle(.menu)
                    } label: {
                        Label(
                            ModelsSettingsRowChrome.priceTierLabel(priceTier),
                            systemImage: "circle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(ModelsSettingsRowChrome.priceTierColor(priceTier))
                    }
                }
                Section(L10n.text("ai_settings.models.online.section.usage")) {
                    NavigationLink {
                        MultiSelectOptionsView(
                            title: L10n.text("ai_settings.models.online.field.scenarios"),
                            options: AIScenario.allCases.map { ($0.rawValue, $0.localizedTitle) },
                            selectedValues: $selectedScenarioRawValues
                        )
                    } label: {
                        HStack {
                            Text(L10n.text("ai_settings.models.online.field.scenarios"))
                            Spacer()
                            Text(selectedScenarioSummary)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        MultiSelectOptionsView(
                            title: L10n.text("ai_settings.models.online.field.tools"),
                            options: SparkToolName.all.map { ($0, SparkToolName.displayName(for: $0)) },
                            selectedValues: $selectedToolNames
                        )
                    } label: {
                        HStack {
                            Text(L10n.text("ai_settings.models.online.field.tools"))
                            Spacer()
                            Text(selectedToolsSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(L10n.text("ai_settings.models.online.section.capabilities")) {
                    formToggleRow(
                        icon: "eye.slash",
                        title: L10n.text("ai_settings.models.online.toggle.default_hidden"),
                        isOn: $isHidden
                    )
                    probeActionRow
                    Text(L10n.text("ai_settings.models.online.probe.cost_note"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    formToggleRow(
                        icon: "character",
                        title: L10n.text("ai_settings.models.online.toggle.supports_text"),
                        isOn: $supportsText
                    )
                    formToggleRow(
                        icon: "photo.on.rectangle.angled",
                        title: L10n.text("ai_settings.field.supports_multimodal"),
                        isOn: $supportsMultimodal
                    )
                    formToggleRow(
                        icon: "atom",
                        title: L10n.text("ai_settings.field.supports_reasoning"),
                        isOn: $supportsReasoning
                    )
                    formToggleRow(
                        icon: "lightbulb",
                        title: L10n.text("ai_settings.field.reasoning_controllable"),
                        isOn: $reasoningControllable
                    )
                    formToggleRow(
                        icon: "hammer",
                        title: L10n.text("ai_settings.field.supports_tool_use"),
                        isOn: $supportsToolUse
                    )
                    formToggleRow(
                        icon: "camera.aperture",
                        title: L10n.text("ai_settings.models.online.toggle.image_gen"),
                        isOn: $supportsImageGen
                    )

                    Text(L10n.text("ai_settings.models.online.capabilities.footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.accentColor)
            .navigationTitle(L10n.text("ai_settings.models.online.nav_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("ai_settings.models.online.save")) { save() }
                }
            }
            .alert(L10n.text("ai_settings.models.online.error_title"), isPresented: $showAlert) {
                Button(L10n.text("common.ok"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showProbeSheet) {
                ModelCapabilityProbeSheet(items: probeItems)
            }
            .onAppear {
                applyInitialDraftIfNeeded()
                if let normalizedInitialCompany,
                   let initialProvider = apiKeyRows.first(where: {
                       $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedInitialCompany
                   })
                {
                    selectedCompany = initialProvider.company
                }
                if selectedCompany.isEmpty, let first = apiKeyRows.first {
                    selectedCompany = first.company
                }
            }
        }
    }

    private var probeActionRow: some View {
        Button {
            Task { await startProbe() }
        } label: {
            HStack(spacing: 12) {
                rowIcon("wand.and.stars")
                Text(L10n.text("ai_settings.models.online.probe.button"))
                    .foregroundStyle(.primary)
                Spacer()
                if isProbing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isProbing || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedProviderForProbe == nil)
    }

    private func formInputRow(
        icon: String? = nil,
        title: String,
        prompt: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            if let icon {
                rowIcon(icon)
            }
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .accessibilityLabel(title)
    }

    private func formToggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            Toggle(title, isOn: isOn)
        }
    }

    private func formMenuRow<Control: View, LabelView: View>(
        icon: String,
        title: String,
        @ViewBuilder control: () -> Control,
        @ViewBuilder label: () -> LabelView
    ) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            Text(title)
            Spacer(minLength: 12)
            
            control()
//            Menu {
//                control()
//            } label: {
//                HStack(spacing: 6) {
//                    label()
//                    Image(systemName: "chevron.up.chevron.down")
//                        .font(.caption2)
//                        .foregroundStyle(.tertiary)
//                }
//            }
        }
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .frame(width: 20)
    }

    private var selectedProviderForProbe: APIKeys? {
        let c = selectedCompany.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return viewModel.snapshot.apiKeys.first(where: {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == c
        })
    }

    private var selectedScenarioSummary: String {
        if selectedScenarioRawValues.isEmpty {
            return L10n.text("ai_settings.models.online.selection.none")
        }
        return "\(selectedScenarioRawValues.count)"
    }

    private var selectedToolsSummary: String {
        let total = SparkToolName.all.count
        if selectedToolNames.count == total {
            return L10n.text("ai_settings.models.online.selection.all")
        }
        return "\(selectedToolNames.count)/\(total)"
    }

    private func applyInitialDraftIfNeeded() {
        guard let initialDraft else { return }
        name = initialDraft.name
        displayName = initialDraft.displayName
        selectedCompany = initialDraft.company
        priceTier = min(max(initialDraft.priceTier, 0), 3)
        isHidden = initialDraft.isHidden
        supportsText = initialDraft.supportsText
        supportsMultimodal = initialDraft.supportsMultimodal
        supportsReasoning = initialDraft.supportsReasoning
        reasoningControllable = initialDraft.reasoningControllable
        supportsToolUse = initialDraft.supportsToolUse
        supportsImageGen = initialDraft.supportsImageGen
        selectedScenarioRawValues = Set(initialDraft.aiScenarios)
        let toolSet = Set(initialDraft.aiToolScenarios.filter { $0.isEmpty == false })
        selectedToolNames = toolSet.isEmpty ? Set(SparkToolName.all) : toolSet
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = selectedCompany.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else {
            alertMessage = L10n.text("ai_settings.models.online.err.api_name")
            showAlert = true
            return
        }
        guard !d.isEmpty else {
            alertMessage = L10n.text("ai_settings.models.online.err.display_name")
            showAlert = true
            return
        }
        guard !c.isEmpty else {
            alertMessage = L10n.text("ai_settings.models.online.err.vendor")
            showAlert = true
            return
        }
        Task {
            let didSave = await viewModel.appendOnlineModelAndPersist(
                name: n,
                displayName: d,
                company: c,
                priceTier: priceTier,
                isHidden: isHidden,
                supportsText: supportsText,
                supportsMultimodal: supportsMultimodal,
                supportsReasoning: supportsReasoning,
                reasoningControllable: reasoningControllable,
                supportsToolUse: supportsToolUse,
                supportsImageGen: supportsImageGen,
                aiScenarios: selectedScenarioRawValues.sorted(),
                aiToolScenarios: selectedToolNames.sorted()
            )
            if didSave {
                await MainActor.run { dismiss() }
            }
        }
    }

    private func startProbe() async {
        guard let provider = selectedProviderForProbe else {
            alertMessage = L10n.text("ai_settings.models.online.err.vendor")
            showAlert = true
            return
        }
        let modelName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelName.isEmpty == false else {
            alertMessage = L10n.text("ai_settings.models.online.err.api_name")
            showAlert = true
            return
        }

        probeItems = ModelCapabilityProbeStep.allCases.map {
            ModelCapabilityProbeProgressItem(step: $0, status: .pending, message: nil)
        }
        isProbing = true
        showProbeSheet = true
        do {
            let summary = try await probeService.probe(
                modelName: modelName,
                provider: provider
            ) { step, status, message in
                await MainActor.run {
                    guard let idx = probeItems.firstIndex(where: { $0.step == step }) else { return }
                    probeItems[idx].status = status
                    probeItems[idx].message = message
                }
            }
            supportsText = summary.supportsText
            supportsMultimodal = summary.supportsMultimodal
            supportsReasoning = summary.supportsReasoning
            reasoningControllable = summary.reasoningControllable
            supportsToolUse = summary.supportsToolUse
            supportsImageGen = summary.supportsImageGen
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
        isProbing = false
    }
}

struct MultiSelectOptionsView: View {
    let title: String
    let options: [(value: String, title: String)]
    @Binding var selectedValues: Set<String>

    var body: some View {
        List {
            ForEach(options, id: \.value) { option in
                Button {
                    if selectedValues.contains(option.value) {
                        selectedValues.remove(option.value)
                    } else {
                        selectedValues.insert(option.value)
                    }
                } label: {
                    HStack {
                        Text(option.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedValues.contains(option.value) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModelCapabilityProbeSheet: View {
    let items: [ModelCapabilityProbeProgressItem]

    var body: some View {
        NavigationView {
            List(items) { item in
                HStack(spacing: 12) {
                    icon(for: item.status)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(item.step.titleKey))
                        if let message = item.message, message.isEmpty == false {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle(L10n.text("ai_settings.models.online.probe.sheet_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func icon(for status: ModelCapabilityProbeStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}
