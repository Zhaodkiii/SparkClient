import SwiftUI

struct OnboardingFlowView: View {
    @StateObject private var viewModel: OnboardingFlowViewModel
    @StateObject private var agentSetupViewModel: OnboardingAgentSetupViewModel
    @ObservedObject private var memberContextStore: MemberContextStore
    @ObservedObject private var aiSettingsViewModel: AISettingsViewModel
    private let homeDependencies: HomeFeatureDependencies?

    init(
        viewModel: OnboardingFlowViewModel,
        memberContextStore: MemberContextStore,
        aiSettingsViewModel: AISettingsViewModel,
        homeDependencies: HomeFeatureDependencies? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _agentSetupViewModel = StateObject(wrappedValue: OnboardingAgentSetupViewModel(aiSettingsViewModel: aiSettingsViewModel))
        self.memberContextStore = memberContextStore
        self.aiSettingsViewModel = aiSettingsViewModel
        self.homeDependencies = homeDependencies
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            VStack(spacing: 0) {
                ZStack {
                    stepView(for: viewModel.currentStep)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.currentStep != .welcome {
                    OnboardingFooter(
                        step: viewModel.currentStep,
                        currentIndex: viewModel.activeSteps.firstIndex(of: viewModel.currentStep) ?? 0,
                        totalCount: viewModel.activeSteps.count,
                        canContinue: viewModel.canGoNext,
                        onContinue: {
                            if viewModel.currentStep == .start {
                                viewModel.complete()
                            } else {
                                viewModel.goNext()
                            }
                        }
                    )
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.currentStep != .welcome && viewModel.currentStep != .profile {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.goBack()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.semibold))
                        }
                        .accessibilityLabel(L10n.text("common.back", fallback: "Back"))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.currentStep.isSkippable {
                        Button(L10n.text("onboarding.action.skip", fallback: "跳过")) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.skip()
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.currentStep)
        }
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep {
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.goNext()
                }
            }
        case .profile:
            OnboardingProfileStep(
                memberContextStore: memberContextStore,
                homeDependencies: homeDependencies
            )
        case .agent:
            OnboardingAgentSetupStep(
                viewModel: agentSetupViewModel,
                aiSettingsViewModel: aiSettingsViewModel
            )
        case .start:
            OnboardingStartStep {
                viewModel.complete()
            }
        }
    }
}

private struct OnboardingWelcomeStep: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(L10n.text("onboarding.welcome.title", fallback: "欢迎来到 Spark"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)

                Text(L10n.text("onboarding.welcome.subtitle", fallback: "用几步完成成员档案与 AI 助手准备，之后就可以开始记录、检索和对话。"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 14) {
                OnboardingFeatureRow(icon: "person.crop.circle.badge.plus", title: L10n.text("onboarding.welcome.profile", fallback: "创建你的第一个健康成员"))
                OnboardingFeatureRow(icon: "brain.head.profile", title: L10n.text("onboarding.welcome.agent", fallback: "了解 AI 助手与模型配置入口"))
                OnboardingFeatureRow(icon: "lock.shield", title: L10n.text("onboarding.welcome.privacy", fallback: "账号级保存进度，可随时回到主流程"))
            }

            Spacer()

            Button(action: onStart) {
                HStack {
                    Text(L10n.text("onboarding.action.start", fallback: "开始设置"))
                        .font(.headline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: 680)
    }
}

private struct OnboardingProfileStep: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let homeDependencies: HomeFeatureDependencies?
    @State private var showCreateMember = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingStepHeader(
                    icon: "person.text.rectangle",
                    title: L10n.text("onboarding.profile.title", fallback: "创建成员档案"),
                    subtitle: L10n.text("onboarding.profile.subtitle", fallback: "Spark 的健康记录、上传和聊天上下文都围绕成员展开。先创建一个成员，后续可以继续添加家人。")
                )

                if memberContextStore.context.members.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("onboarding.profile.empty.title", fallback: "还没有成员"))
                            .font(.headline)
                        Text(L10n.text("onboarding.profile.empty.body", fallback: "添加姓名、关系、性别和生日后，就能把病历、体检、用药记录绑定到这个成员。"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        ForEach(memberContextStore.context.members) { member in
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.headline)
                                    Text(MemberRelationshipCatalog.displayTitle(for: member.relationship))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.green)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                Button {
                    showCreateMember = true
                } label: {
                    Label(L10n.text("onboarding.profile.add", fallback: "添加成员"), systemImage: "plus")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .fullScreenCover(isPresented: $showCreateMember) {
            CompatibleNavigationContainer(legacyStackStyle: true) {
                Group {
                    if let homeDependencies {
                        MemberSetupFlowView(store: memberContextStore, homeDependencies: homeDependencies)
                    } else {
                        AddFamilyMemberView(mode: .create, store: memberContextStore)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                // 右上角关闭按钮
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showCreateMember = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                }
            }
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

private struct OnboardingStartStep: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(Color.green)
            VStack(spacing: 10) {
                Text(L10n.text("onboarding.start.title", fallback: "准备好了"))
                    .font(.largeTitle.bold())
                Text(L10n.text("onboarding.start.subtitle", fallback: "成员档案已经就绪。进入 Spark 后，可以继续上传医疗文档、创建知识库或开始一段 AI 对话。"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer()
            Button(action: onStart) {
                Text(L10n.text("onboarding.action.enter", fallback: "进入 Spark"))
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: 640)
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

private struct OnboardingStepHeader: View {
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

private struct OnboardingFeatureRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 26, height: 26)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
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
