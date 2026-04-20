import SwiftUI

/// 对齐 Health `AddOnlineModelView`：表单添加云端模型（无 SwiftData）。
struct AddOnlineModelSheet: View {
    @ObservedObject var viewModel: AISettingsViewModel
    @Environment(\.dismiss) private var dismiss
    let initialCompany: String?

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
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showProbeSheet = false
    @State private var probeItems: [ModelCapabilityProbeProgressItem] = ModelCapabilityProbeStep.allCases.map {
        ModelCapabilityProbeProgressItem(step: $0, status: .pending, message: nil)
    }
    @State private var isProbing = false

    private let probeService = ClientModelCapabilityProbeService()

    init(viewModel: AISettingsViewModel, initialCompany: String? = nil) {
        self.viewModel = viewModel
        self.initialCompany = initialCompany
    }

    private var apiKeyRows: [APIKeys] {
        viewModel.snapshot.apiKeys.filter {
            !$0.isHidden &&
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != LocalModelService.localCompany.uppercased()
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(L10n.text("ai_settings.models.online.section.basic")) {
                    TextField(L10n.text("ai_settings.models.online.field.api_name"), text: $name)
                    TextField(L10n.text("ai_settings.models.online.field.display_name"), text: $displayName)
                    Picker(L10n.text("ai_settings.models.online.field.vendor"), selection: $selectedCompany) {
                        ForEach(apiKeyRows, id: \.id) { key in
                            Text(key.name.isEmpty ? key.company : key.name)
                                .tag(key.company)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(L10n.text("ai_settings.models.online.section.price")) {
                    Picker(L10n.text("ai_settings.field.price_tier"), selection: $priceTier) {
                        Text(L10n.text("ai_settings.field.price_tier.free")).tag(0)
                        Text(L10n.text("ai_settings.field.price_tier.economy")).tag(1)
                        Text(L10n.text("ai_settings.field.price_tier.standard")).tag(2)
                        Text(L10n.text("ai_settings.field.price_tier.premium")).tag(3)
                    }
                    .pickerStyle(.menu)
                }
                Section(L10n.text("ai_settings.models.online.section.capabilities")) {
                    Toggle(L10n.text("ai_settings.models.online.toggle.default_hidden"), isOn: $isHidden)
                    Toggle(L10n.text("ai_settings.models.online.toggle.supports_text"), isOn: $supportsText)
                    Toggle(L10n.text("ai_settings.field.supports_multimodal"), isOn: $supportsMultimodal)
                    Toggle(L10n.text("ai_settings.field.supports_reasoning"), isOn: $supportsReasoning)
                    Toggle(L10n.text("ai_settings.field.reasoning_controllable"), isOn: $reasoningControllable)
                    Toggle(L10n.text("ai_settings.field.supports_tool_use"), isOn: $supportsToolUse)
                    Toggle(L10n.text("ai_settings.models.online.toggle.image_gen"), isOn: $supportsImageGen)

                    Button {
                        Task { await startProbe() }
                    } label: {
                        HStack {
                            Label(L10n.text("ai_settings.models.online.probe.button"), systemImage: "wand.and.stars")
                            Spacer()
                            if isProbing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isProbing || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedProviderForProbe == nil)

                    Text(L10n.text("ai_settings.models.online.probe.cost_note"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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
                if let initialCompany,
                   apiKeyRows.contains(where: { $0.company == initialCompany }) {
                    selectedCompany = initialCompany
                }
                if selectedCompany.isEmpty, let first = apiKeyRows.first {
                    selectedCompany = first.company
                }
            }
        }
    }

    private var selectedProviderForProbe: APIKeys? {
        let c = selectedCompany.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return viewModel.snapshot.apiKeys.first(where: {
            $0.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == c
        })
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
        viewModel.appendOnlineModel(
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
            supportsImageGen: supportsImageGen
        )
        Task {
            await viewModel.persistSnapshotNow()
            await MainActor.run { dismiss() }
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
