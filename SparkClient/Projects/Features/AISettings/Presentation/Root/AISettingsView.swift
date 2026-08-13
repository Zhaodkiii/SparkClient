import SwiftUI

struct AISettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        List {
            Section(L10n.text("ai_settings.section.model")) {
                MainNavigationLink {
                    APIKeysSettingsView(viewModel: viewModel)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.api_keys"),
                        subtitle: L10n.text("ai_settings.row.api_keys.subtitle"),
                        icon: "key.2.on.ring"
                    )
                }

                MainNavigationLink {
                    ModelsSettingsView(viewModel: viewModel)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.models"),
                        subtitle: L10n.text("ai_settings.row.models.subtitle"),
                        icon: "square.stack.3d.up"
                    )
                }

                MainNavigationLink {
                    AIModelPreferencesView(
                        viewModel: viewModel.makeScenarioModelPreferencesViewModel()
                    )
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.default_model_config"),
                        subtitle: L10n.text("ai_settings.row.default_model_config.subtitle"),
                        icon: "slider.horizontal.3"
                    )
                }
            }

            Section(L10n.text("ai_settings.section.tools")) {
                MainNavigationLink {
                    SmallTasksSettingsView(viewModel: viewModel)
                } label: {
                    SettingNavRow(
                        title: "小任务",
                        subtitle: "维护本地小任务并关联到模型",
                        icon: "checklist"
                    )
                }

                MainNavigationLink {
                    AISearchToolSettingsView(viewModel: viewModel)
                        .hidesMainTabBarWhenPushed()
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.search_tools"),
                        subtitle: L10n.text("ai_settings.row.search_tools.subtitle"),
                        icon: "magnifyingglass"
                    )
                }

                MainNavigationLink {
                    AIToolSettingsView(viewModel: viewModel)
                        .hidesMainTabBarWhenPushed()
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.ai_tools", fallback: "AI 工具"),
                        subtitle: L10n.text("ai_settings.row.ai_tools.subtitle", fallback: "查看 DeepTutorChat 与 Chat 可调用工具"),
                        icon: "wrench.and.screwdriver"
                    )
                }

                MainNavigationLink {
                    AIWeatherToolSettingsView(viewModel: viewModel)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.weather.nav_title", fallback: "天气查询"),
                        subtitle: L10n.text("ai_settings.row.weather_tools.subtitle", fallback: "配置 QWeather、OpenWeather 与 Apple Weather"),
                        icon: "cloud.sun.fill"
                    )
                }
            }

            #if DEBUG
            Section("Chat 会话设置") {
                ChatConversationUIArchitectureSettingsSection(viewModel: viewModel)
                ChatConversationAppearanceSettingsSection(viewModel: viewModel)
                ChatComposerStartupSettingsSection(viewModel: viewModel)
            }

            Section("DeepTutorChat 对话外观") {
                DeepTutorConversationAppearanceSettingsSection(viewModel: viewModel)
            }
            #endif

            // 当前版本 功能不完善 ，暂时关闭
            Section(L10n.text("ai_settings.section.personalization")) {
                NavigationLink {
                    PromptRepoSettingsView(
                        promptRepo: $viewModel.snapshot.promptRepo,
                        onPersistRequested: {
                            Task { await viewModel.persistPromptRepoNow() }
                        }
                    )
                        .hidesMainTabBarWhenPushed()
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.prompt_repo"),
                        subtitle: L10n.text("ai_settings.row.prompt_repo.subtitle"),
                        icon: "tray.full"
                    )
                }

                NavigationLink {
                    MemoryArchiveSettingsView(viewModel: viewModel.makeMemoryArchiveSettingsViewModel())
                        .hidesMainTabBarWhenPushed()
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.memory_archive"),
                        subtitle: L10n.text("ai_settings.row.memory_archive.subtitle"),
                        icon: "archivebox"
                    )
                }

                NavigationLink {
                    TranslationDicSettingsView(translationDic: $viewModel.snapshot.translationDic)
                        .hidesMainTabBarWhenPushed()
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.translation_dic"),
                        subtitle: L10n.text("ai_settings.row.translation_dic.subtitle"),
                        icon: "character.book.closed"
                    )
                }
            }
        }
        .navigationTitle(L10n.text("ai_settings.title"))
    
        .task {
            await viewModel.load()
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { presented in
                if presented == false {
                    viewModel.clearError()
                }
            }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
     
    }
}

private struct SettingNavRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ChatConversationUIArchitectureSettingsSection: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        Picker("UI 架构", selection: Binding(
            get: { viewModel.snapshot.chatConversationUIPreferences.architecture },
            set: { newValue in
                viewModel.snapshot.chatConversationUIPreferences.architecture = newValue
                ChatConversationUIDevicePreferencesStore.save(viewModel.snapshot.chatConversationUIPreferences)
                Task { await viewModel.persistSnapshotNow() }
            }
        )) {
            ForEach(ChatConversationUIArchitecture.allCases, id: \.self) { architecture in
                Text(architecture.displayName).tag(architecture)
            }
        }

        if viewModel.snapshot.chatConversationUIPreferences.architecture == .swiftUI {
            Picker("SwiftUI 刷新策略", selection: Binding(
                get: { viewModel.snapshot.chatConversationUIPreferences.swiftUIRefreshBehavior },
                set: { newValue in
                    viewModel.snapshot.chatConversationUIPreferences.swiftUIRefreshBehavior = newValue
                    ChatConversationUIDevicePreferencesStore.save(viewModel.snapshot.chatConversationUIPreferences)
                    Task { await viewModel.persistSnapshotNow() }
                }
            )) {
                ForEach(ChatSwiftUIRefreshBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }
        }

        Picker("数据授权", selection: Binding(
            get: { viewModel.snapshot.chatToolInteractionPreferences.consentPresentationMode },
            set: { newValue in
                viewModel.snapshot.chatToolInteractionPreferences.consentPresentationMode = newValue
                ChatToolInteractionDevicePreferencesStore.save(viewModel.snapshot.chatToolInteractionPreferences)
                Task { await viewModel.persistSnapshotNow() }
            }
        )) {
            ForEach(ChatToolInteractionPresentationMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
    }
}
private struct ChatConversationAppearanceSettingsSection: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        Picker("对话卡片样式", selection: Binding(
            get: { viewModel.snapshot.chatConversationAppearance.cardStyle },
            set: { newValue in
                viewModel.snapshot.chatConversationAppearance.cardStyle = newValue
                ChatConversationAppearanceDevicePreferencesStore.save(viewModel.snapshot.chatConversationAppearance)
                Task { await viewModel.persistSnapshotNow() }
            }
        )) {
            ForEach(ChatConversationCardStyle.allCases, id: \.self) { style in
                Text(style.displayName).tag(style)
            }
        }

        Picker("工具调用展示", selection: Binding(
            get: { viewModel.snapshot.chatConversationAppearance.toolTraceDisplayMode },
            set: { newValue in
                viewModel.snapshot.chatConversationAppearance.toolTraceDisplayMode = newValue
                ChatConversationAppearanceDevicePreferencesStore.save(viewModel.snapshot.chatConversationAppearance)
                Task { await viewModel.persistSnapshotNow() }
            }
        )) {
            ForEach(ChatToolTraceDisplayMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }

        Toggle("流式过程也折叠", isOn: Binding(
            get: { viewModel.snapshot.chatConversationAppearance.collapseToolsWhileStreaming },
            set: { newValue in
                viewModel.snapshot.chatConversationAppearance.collapseToolsWhileStreaming = newValue
                ChatConversationAppearanceDevicePreferencesStore.save(viewModel.snapshot.chatConversationAppearance)
                Task { await viewModel.persistSnapshotNow() }
            }
        ))

        if viewModel.snapshot.chatConversationAppearance.cardStyle == .bodyFocused {
            Toggle("工具结果卡片显示在正文", isOn: Binding(
                get: { viewModel.snapshot.chatConversationAppearance.separatesToolPresentationsInBodyFocused },
                set: { newValue in
                    viewModel.snapshot.chatConversationAppearance.separatesToolPresentationsInBodyFocused = newValue
                    ChatConversationAppearanceDevicePreferencesStore.save(viewModel.snapshot.chatConversationAppearance)
                    Task { await viewModel.persistSnapshotNow() }
                }
            ))
        }
    }
}

private struct ChatComposerStartupSettingsSection: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("默认启动配置")
                .font(.headline)

            Text("新进入 Chat 会话时，下面这些开关会作为初始状态。配置按登录账号保存。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle("默认启用成员档案", isOn: Binding(
                get: { viewModel.snapshot.chatComposerStartupPreferences.memberProfileEnabled },
                set: { newValue in
                    viewModel.snapshot.chatComposerStartupPreferences.memberProfileEnabled = newValue
                    Task { await viewModel.persistSnapshotNow() }
                }
            ))

            Toggle("默认启用工具", isOn: Binding(
                get: { viewModel.snapshot.chatComposerStartupPreferences.useTools },
                set: { newValue in
                    viewModel.snapshot.chatComposerStartupPreferences.useTools = newValue
                    Task { await viewModel.persistSnapshotNow() }
                }
            ))

            Toggle("默认启用知识库", isOn: Binding(
                get: { viewModel.snapshot.chatComposerStartupPreferences.useKnowledgeBag },
                set: { newValue in
                    viewModel.snapshot.chatComposerStartupPreferences.useKnowledgeBag = newValue
                    Task { await viewModel.persistSnapshotNow() }
                }
            ))

            Toggle("默认启用联网搜索", isOn: Binding(
                get: { viewModel.snapshot.chatComposerStartupPreferences.useWebSearch },
                set: { newValue in
                    viewModel.snapshot.chatComposerStartupPreferences.useWebSearch = newValue
                    Task { await viewModel.persistSnapshotNow() }
                }
            ))

            Toggle("默认启用深度思考", isOn: Binding(
                get: { viewModel.snapshot.chatComposerStartupPreferences.reasoningEnabled },
                set: { newValue in
                    viewModel.snapshot.chatComposerStartupPreferences.reasoningEnabled = newValue
                    Task { await viewModel.persistSnapshotNow() }
                }
            ))

            Picker("默认思考强度", selection: Binding(
                get: { viewModel.snapshot.chatComposerStartupPreferences.reasoningEffortTier },
                set: { newValue in
                    viewModel.snapshot.chatComposerStartupPreferences.reasoningEffortTier = newValue
                    Task { await viewModel.persistSnapshotNow() }
                }
            )) {
                Text("0 - 不思考").tag(0)
                Text("1 - 低").tag(1)
                Text("2 - 中").tag(2)
                Text("3 - 高").tag(3)
            }
            .pickerStyle(.menu)
        }
    }
}

private struct DeepTutorConversationAppearanceSettingsSection: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        Picker("对话卡片样式", selection: Binding(
            get: { viewModel.snapshot.deepTutorConversationAppearance.cardStyle },
            set: { newValue in
                viewModel.snapshot.deepTutorConversationAppearance.cardStyle = newValue
                Task { await viewModel.persistSnapshotNow() }
            }
        )) {
            ForEach(DeepTutorConversationCardStyle.allCases, id: \.self) { style in
                Text(style.displayName).tag(style)
            }
        }

        Picker("工具调用展示", selection: Binding(
            get: { viewModel.snapshot.deepTutorConversationAppearance.toolTraceDisplayMode },
            set: { newValue in
                viewModel.snapshot.deepTutorConversationAppearance.toolTraceDisplayMode = newValue
                Task { await viewModel.persistSnapshotNow() }
            }
        )) {
            ForEach(DeepTutorToolTraceDisplayMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }

        Toggle("流式过程也折叠", isOn: Binding(
            get: { viewModel.snapshot.deepTutorConversationAppearance.collapseToolsWhileStreaming },
            set: { newValue in
                viewModel.snapshot.deepTutorConversationAppearance.collapseToolsWhileStreaming = newValue
                Task { await viewModel.persistSnapshotNow() }
            }
        ))
    }
}
