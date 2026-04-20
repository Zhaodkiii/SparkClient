import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct APIKeysSettingsView: View {
    @Binding var snapshot: AISettingsSnapshot
    @ObservedObject var viewModel: AISettingsViewModel

    @State private var showAddCustomProvider = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isTesting = false
    @State private var testingProviderID: UUID?
    @State private var testResultByID: [UUID: Bool] = [:]
    @State private var trialPrivacyAccepted = false

    private var sortedProviders: [APIKeys] {
        let filtered = snapshot.apiKeys.filter { $0.company.uppercased() != "LOCAL" }
        let grouped = Dictionary(grouping: filtered, by: { $0.company.uppercased() })
        return grouped.values
            .compactMap { $0.first }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var isSignedIn: Bool {
        // API settings页只在登录会话中出现；保持保守判定，避免出现误导按钮。
        true
    }

    private var trialProviders: [APIKeys] {
        guard snapshot.trial.isActive else { return [] }

        let endpoints = Set(snapshot.trialModelPolicy.map { $0.config.endpoint.lowercased() })
        let list = snapshot.apiKeys.filter { provider in
            endpoints.contains(provider.requestURL.lowercased())
        }
        let grouped = Dictionary(grouping: list, by: { $0.company.uppercased() })
        return grouped.values.compactMap { $0.first }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                trialEntryCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if snapshot.trial.isActive, trialProviders.isEmpty == false {
                Section("试用期可用厂商") {
                    ForEach(trialProviders) { provider in
                        HStack(spacing: 12) {
                            Image(companyIconName(for: provider.company))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text(localizedProviderName(provider))
                                .font(.body)
                            Spacer()
                            Text("试用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("仅展示服务端试用策略内厂商，不支持本地编辑")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("模型厂商") {
                Button {
                    showAddCustomProvider = true
                } label: {
                    Label("新增自定义供应商", systemImage: "plus.circle.fill")
                        .font(.body)
                }

                ForEach(sortedProviders) { provider in
                    providerRow(provider)
                }
            }
        }
        .navigationTitle("模型密钥")
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showAddCustomProvider) {
            AddCustomProviderSheet { newProvider in
                snapshot.apiKeys.append(newProvider)
                impact(.medium)
                Task { await viewModel.persistSnapshotNow() }
            }
        }
        .alert("提示", isPresented: $showErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await viewModel.refreshTrialStatus()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snapshot.apiKeys)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snapshot.trial)
    }

    private var trialEntryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "key.radiowaves.forward.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型密钥 / 试用权限")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("配置 API Key 后可启用对应模型能力")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                trialConsentArea
                trialActionButton
            }

            modelBadges
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var statusLabel: some View {
        Group {
            switch snapshot.trial.status {
            case "active":
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("试用已开通")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if snapshot.trial.remainingSeconds > 0 {
                        Text("剩余 \(daysRemainingText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            case "pending":
                Label("申请审核中", systemImage: "clock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            case "rejected":
                Label("申请未通过，可再次申请", systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            case "expired":
                Label("试用已过期，可重新申请", systemImage: "hourglass.bottomhalf.filled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            default:
                Label("新用户可申请试用", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var daysRemainingText: String {
        let days = max(Int(ceil(Double(snapshot.trial.remainingSeconds) / 86_400.0)), 0)
        return "\(days) 天"
    }

    private var trialConsentArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("提交试用申请前，请确认已阅读相关厂商隐私说明。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle(isOn: $trialPrivacyAccepted) {
                Text("我已阅读并同意相关隐私条款")
                    .font(.footnote)
            }
            .tint(.accentColor)
        }
    }

    private var trialActionButton: some View {
        Button {
            guard trialPrivacyAccepted else {
                showError("请先勾选隐私同意后再提交申请")
                return
            }
            Task {
                let ok = await viewModel.submitTrialApplication()
                if ok {
                    impact(.medium)
                }
            }
        } label: {
            HStack {
                if viewModel.trialOperationInFlight {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                Text(trialButtonTitle)
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.trialOperationInFlight || !isSignedIn)
    }

    private var trialButtonTitle: String {
        switch snapshot.trial.status {
        case "active": return "已开通"
        case "pending": return "审核中"
        case "rejected", "expired": return "再次申请"
        default: return "提交申请"
        }
    }

    private var modelBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["OpenAI", "Gemini", "Claude", "DeepSeek", "GLM"], id: \.self) { title in
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                }
            }
        }
    }

    private func providerRow(_ provider: APIKeys) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                ProviderSettingsEditorView(
                    provider: provider,
                    viewModel: viewModel,
                    onDeleteModel: { modelID in
                        deleteModel(modelID: modelID)
                    },
                    onToggleModelVisibility: { modelID, visible in
                        guard let index = snapshot.allModels.firstIndex(where: { $0.id == modelID }) else { return }
                        snapshot.allModels[index].isHidden = !visible
                        Task { await viewModel.persistSnapshotNow() }
                    },
                    hasValidAPIKeyForModel: { model in
                        hasValidAPIKey(for: model)
                    },
                    onSave: { updated in
                        saveProvider(updated)
                    },
                    onTest: { candidate in
                        await testProvider(candidate)
                    }
                )
            } label: {
                HStack(spacing: 12) {
                    Image(companyIconName(for: provider.company))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(localizedProviderName(provider))
                        .font(.body)
                    Spacer()
                    if provider.source == .custom {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle("", isOn: Binding(
                get: { provider.isHidden == false },
                set: { newValue in
                    setProviderEnabled(providerID: provider.id, enabled: newValue)
                }
            ))
            .labelsHidden()
            .tint(.accentColor)
        }
        .overlay(alignment: .trailing) {
            if testingProviderID == provider.id, isTesting {
                ProgressView().padding(.trailing, 56)
            }
        }
    }

    private func hasValidAPIKey(for model: AllModels) -> Bool {
        let company = model.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard company.isEmpty == false else { return false }
        return snapshot.apiKeys.contains { key in
            key.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == company &&
            key.isHidden == false &&
            key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func deleteModel(modelID: UUID) {
        guard let index = snapshot.allModels.firstIndex(where: { $0.id == modelID }) else { return }
        if snapshot.allModels[index].source == .system {
            showError("系统模型不支持删除")
            return
        }
        snapshot.allModels.remove(at: index)
        Task { await viewModel.persistSnapshotNow() }
    }

    private func setProviderEnabled(providerID: UUID, enabled: Bool) {
        guard let index = snapshot.apiKeys.firstIndex(where: { $0.id == providerID }) else { return }
        let provider = snapshot.apiKeys[index]

        if enabled && provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showError("\(localizedProviderName(provider)) 需要先配置有效 API Key")
            return
        }

        snapshot.apiKeys[index].isHidden = !enabled
        snapshot.apiKeys[index].timestamp = Date()
        updateModelVisibility(company: provider.company, hidden: !enabled)
        impact(.light)
        Task { await viewModel.persistSnapshotNow() }
    }

    private func saveProvider(_ provider: APIKeys) {
        guard let index = snapshot.apiKeys.firstIndex(where: { $0.id == provider.id }) else { return }
        snapshot.apiKeys[index] = provider
        snapshot.apiKeys[index].timestamp = Date()
        snapshot.apiKeys[index].isHidden = provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        updateModelVisibility(company: provider.company, hidden: snapshot.apiKeys[index].isHidden)
        impact(.medium)
        Task { await viewModel.persistSnapshotNow() }
    }

    private func testProvider(_ provider: APIKeys) async -> Bool {
        let key = provider.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            await MainActor.run {
                showError("请先输入 API Key")
            }
            return false
        }

        await MainActor.run {
            isTesting = true
            testingProviderID = provider.id
            testResultByID[provider.id] = nil
        }

        let ok = await viewModel.testProviderConnection(
            requestURL: provider.requestURL,
            apiKey: key,
            model: "spark-chat-default"
        )

        await MainActor.run {
            isTesting = false
            testingProviderID = nil
            testResultByID[provider.id] = ok
            if ok == false {
                showError("连接测试失败，请检查 URL 或密钥")
            } else {
                impact(.medium)
            }
        }
        return ok
    }

    private func updateModelVisibility(company: String, hidden: Bool) {
        for index in snapshot.allModels.indices where snapshot.allModels[index].company.uppercased() == company.uppercased() {
            snapshot.allModels[index].isHidden = hidden
        }
    }

    private func localizedProviderName(_ provider: APIKeys) -> String {
        if provider.source == .custom {
            return provider.displayName
        }
        let key = "company_\(provider.company.uppercased())"
        let localized = L10n.text(key)
        return localized == key ? provider.displayName : localized
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

private struct AddCustomProviderSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var key = ""
    @State private var requestURL = ""
    @State private var errorMessage: String?

    let onSave: (APIKeys) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("供应商名称", text: $name)
                    SecureField("API Key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("请求地址", text: $requestURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    if requestURL.isEmpty == false, requestURL.hasSuffix("/v1/chat/completions") == false {
                        Button("补全 /v1/chat/completions") {
                            var base = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            while base.hasSuffix("/") { base.removeLast() }
                            requestURL = "\(base)/v1/chat/completions"
                        }
                        .font(.footnote)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("新增自定义供应商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard validate() else { return }
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let normalizedCompany = "CUSTOM_\(UUID().uuidString.prefix(8).uppercased())"
                        let provider = APIKeys(
                            name: trimmedName,
                            company: normalizedCompany,
                            key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                            requestURL: requestURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            isHidden: false,
                            help: "自定义 OpenAI-compatible 供应商",
                            source: .custom,
                            timestamp: Date()
                        )
                        onSave(provider)
                        dismiss()
                    }
                    .disabled(!isBasicInputFilled)
                }
            }
        }
    }

    private var isBasicInputFilled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func validate() -> Bool {
        let url = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else {
            errorMessage = "请求地址必须以 http:// 或 https:// 开头"
            return false
        }
        errorMessage = nil
        return true
    }
}
