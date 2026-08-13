import SwiftUI

struct OnboardingFlowView: View {
    @StateObject private var viewModel: OnboardingFlowViewModel
    @ObservedObject private var memberContextStore: MemberContextStore
    @ObservedObject private var aiSettingsViewModel: AISettingsViewModel
    @State private var didBootstrapDefaultMember = false
    private let homeDependencies: HomeFeatureDependencies?
    private let onCompleted: () -> Void

    init(
        viewModel: OnboardingFlowViewModel,
        memberContextStore: MemberContextStore,
        aiSettingsViewModel: AISettingsViewModel,
        homeDependencies: HomeFeatureDependencies? = nil,
        onCompleted: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.memberContextStore = memberContextStore
        self.aiSettingsViewModel = aiSettingsViewModel
        self.homeDependencies = homeDependencies
        self.onCompleted = onCompleted
    }

    var body: some View {
        CompatibleRouteNavigationContainer(path: $viewModel.navigationPath, legacyStackStyle: true) {
            OnboardingWelcomeStep {
                viewModel.goNext()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        } destination: { step in
            onboardingDestination(for: step)
        }
//        .task {
//            await bootstrapDefaultMemberIfNeeded()
//        }
    }

    @ViewBuilder
    private func onboardingDestination(for step: OnboardingStep) -> some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome:
                    EmptyView()
                case .reportGuide:
                    OnboardingAIReportGuideStep {
                        viewModel.goNext()
                    }
                case .medicationGuide:
                    OnboardingMedicationGuideStep {
                        viewModel.goNext()
                    }
                case .profile:
                    OnboardingProfileStep(
                        memberContextStore: memberContextStore,
                        homeDependencies: homeDependencies,
                        onContinue: {
                            viewModel.goNext()
                        }
                    )
                case .start:
                    OnboardingStartStep {
                        viewModel.complete()
                        onCompleted()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

//            OnboardingFooter(
//                step: step,
//                currentIndex: viewModel.activeSteps.firstIndex(of: step) ?? 0,
//                totalCount: viewModel.activeSteps.count,
//                canContinue: viewModel.canGoNext,
//                onContinue: {
//                    if step == .start {
//                        viewModel.complete()
//                        onCompleted()
//                    } else {
//                        viewModel.goNext()
//                    }
//                }
//            )
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
//        .navigationBarBackButtonHidden(step == .profile)
        .toolbar {
//            ToolbarItem(placement: .navigationBarLeading) {
//                if step != .profile {
//                    Button {
//                        viewModel.goBack()
//                    } label: {
//                        Image(systemName: "chevron.left")
//                            .font(.headline.weight(.semibold))
//                    }
//                    .accessibilityLabel(L10n.text("common.back", fallback: "Back"))
//                }
//            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if step.isSkippable {
                    Button(L10n.text("onboarding.action.skip", fallback: "跳过")) {
                        viewModel.skip()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func bootstrapDefaultMemberIfNeeded() async {
        guard didBootstrapDefaultMember == false else { return }
        guard memberContextStore.context.members.isEmpty else { return }
        guard let homeDependencies else { return }

        didBootstrapDefaultMember = true

        let created = await memberContextStore.addMember(
            name: "初始成员",
            relationship: "self",
            gender: "male",
            birthDate: nil
        )
        guard let member = created else {
            didBootstrapDefaultMember = false
            return
        }
        
        viewModel.complete()
        onCompleted()

        do {
            _ = try await homeDependencies.memberModuleSetupUseCase.saveModuleSetting(
                memberID: member.id,
                moduleCode: MemberSetupModule.medical.rawValue,
                isEnabled: true,
                isCompleted: false,
                displayOrder: MemberSetupModule.medical.displayOrder,
                summaryText: ""
            )
            memberContextStore.select(memberID: member.id)
        } catch {
            didBootstrapDefaultMember = false
        }
    }
}

private struct OnboardingAgentSetupStep: View {
    @ObservedObject var viewModel: OnboardingAgentSetupViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @State private var activeSheetRoute: AgentSheetRoute?

    private enum AgentSheetRoute: Identifiable {
        case create
        case edit(AllModels)

        var id: String {
            switch self {
            case .create:
                return "create"
            case .edit(let agent):
                return "edit-\(agent.id)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingStepHeader(
                    icon: "brain.head.profile",
                    title: L10n.text("onboarding.agent.title", fallback: "配置智能体"),
                    subtitle: L10n.text("onboarding.agent.subtitle", fallback: "选择一个健康模板，Spark 会基于你的对话模型创建专属 AI 助手。你也可以创建自定义智能体，之后仍可在 AI 设置中编辑。")
                )

                if aiSettingsViewModel.isLoading {
                    ProgressView(L10n.text("app.loading.preparing"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    baseModelSection
                    createdAgentsSection
                    templateSection
                }

                Text(L10n.text("onboarding.agent.note", fallback: "这一步不会阻塞你进入主界面。默认配置会先工作，精细化配置可以在「设置 > AI 设置」中完成。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(item: $activeSheetRoute) { route in
            CompatibleNavigationContainer(legacyStackStyle: true) {
                switch route {
                case .create:
                    ModelsSettingsAgentSheet(
                        baseModels: viewModel.baseModels,
                        scenarioBindings: viewModel.scenarioBindings,
                        smallTasks: viewModel.smallTasks,
                        promptTooling: viewModel.promptTooling,
                        promptTemplates: viewModel.promptTemplates,
                        onCreate: viewModel.createCustomAgent,
                        onUpdate: nil
                    )
                case .edit(let agent):
                    ModelsSettingsAgentSheet(
                        baseModels: viewModel.baseModels,
                        editingAgent: agent,
                        scenarioBindings: viewModel.scenarioBindings,
                        smallTasks: viewModel.smallTasks,
                        promptTooling: viewModel.promptTooling,
                        promptTemplates: viewModel.promptTemplates,
                        onCreate: viewModel.createCustomAgent,
                        onUpdate: viewModel.updateAgent,
                        onPersistScenarioBindings: { change in
                            viewModel.persistScenarioBindingChange(change)
                        }
                    )
                }
            }
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if $0 == false { viewModel.errorMessage = nil } }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var baseModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("onboarding.agent.base_model.title", fallback: "基座模型"))
                .font(.headline)

            if viewModel.baseModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.text("onboarding.agent.no_base_model.title", fallback: "暂无可用对话模型"), systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.text("onboarding.agent.no_base_model.body", fallback: "你可以先跳过智能体配置，进入主界面后在「设置 > AI 设置」中添加 API Key 或本地模型。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Picker(L10n.text("onboarding.agent.base_model.picker", fallback: "选择基座模型"), selection: $viewModel.selectedBaseModelName) {
                    ForEach(viewModel.baseModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                .pickerStyle(.menu)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var createdAgentsSection: some View {
        if viewModel.agents.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.text("onboarding.agent.created.title", fallback: "已创建的智能体"))
                        .font(.headline)
                    Spacer()
                    Button {
                        activeSheetRoute = .create
                    } label: {
                        Label(L10n.text("onboarding.agent.action.custom", fallback: "自定义"), systemImage: "plus")
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(viewModel.baseModels.isEmpty)
                }

                VStack(spacing: 10) {
                    ForEach(viewModel.agents) { agent in
                        CreatedAgentRow(
                            agent: agent,
                            onEdit: { activeSheetRoute = .edit(agent) },
                            onDelete: { viewModel.deleteAgent(agent) }
                        )
                    }
                }
            }
        }
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("onboarding.agent.templates.title", fallback: "健康智能体模板"))
                    .font(.headline)
                Spacer()
                if viewModel.agents.isEmpty {
                    Button {
                        activeSheetRoute = .create
                    } label: {
                        Label(L10n.text("onboarding.agent.action.custom", fallback: "自定义"), systemImage: "plus")
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(viewModel.baseModels.isEmpty)
                }
            }

            ForEach(OnboardingAgentTemplates.all) { template in
                AgentTemplateCard(
                    template: template,
                    isCreating: viewModel.isCreating,
                    isDisabled: viewModel.baseModels.isEmpty
                ) {
                    Task {
                        _ = await viewModel.createAgent(from: template)
                    }
                }
            }
        }
    }
}

private struct CreatedAgentRow: View {
    let agent: AllModels
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: agent.iconSymbol ?? "brain.head.profile")
                .font(.title3)
                .frame(width: 36, height: 36)
                .foregroundStyle(Color.accentColor)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.displayName)
                    .font(.subheadline.weight(.semibold))
                if let base = agent.baseModelName {
                    Text(base)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Menu {
                Button(L10n.text("common.edit", fallback: "编辑"), action: onEdit)
                Button(L10n.text("common.delete", fallback: "删除"), role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AgentTemplateCard: View {
    let template: OnboardingAgentTemplate
    let isCreating: Bool
    let isDisabled: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(templatePrimaryColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(template.displayName)
                        .font(.headline)
                    Text(template.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                Spacer(minLength: 0)
            }

            Text(template.quote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: onCreate) {
                HStack {
                    if isCreating {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.circle.fill")
                        Text(L10n.text("onboarding.agent.action.create_from_template", fallback: "使用模板创建"))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(isDisabled ? Color(.systemGray3) : templatePrimaryColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || isCreating)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var templatePrimaryColor: Color {
        Color(onboardingHex: template.tint.primary) ?? Color.accentColor
    }
}


private struct OnboardingFooter: View {
    let step: OnboardingStep
    let currentIndex: Int
    let totalCount: Int
    let canContinue: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(currentIndex + 1), total: Double(totalCount))
                .tint(Color.accentColor)

            HStack {
                Text("\(currentIndex + 1) / \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text(step == .start ? L10n.text("onboarding.action.enter", fallback: "进入 Spark") : L10n.text("common.next", fallback: "下一步"))
                        Image(systemName: step == .start ? "checkmark" : "arrow.right")
                    }
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(canContinue ? Color.accentColor : Color(.systemGray3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(canContinue == false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.bar)
    }
}

struct OnboardingStepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Color {
    init?(onboardingHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
