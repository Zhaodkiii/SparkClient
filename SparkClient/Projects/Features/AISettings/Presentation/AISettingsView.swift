import SwiftUI

struct AISettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        List {
            Section(L10n.text("ai_settings.section.model")) {
                NavigationLink {
                    APIKeysSettingsView(apiKeys: $viewModel.snapshot.apiKeys)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.api_keys"),
                        subtitle: L10n.text("ai_settings.row.api_keys.subtitle"),
                        icon: "key.2.on.ring"
                    )
                }

                NavigationLink {
                    ModelsSettingsView(models: $viewModel.snapshot.allModels)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.models"),
                        subtitle: L10n.text("ai_settings.row.models.subtitle"),
                        icon: "square.stack.3d.up"
                    )
                }

                NavigationLink {
                    AIModelPreferencesView(
                        userInfo: $viewModel.snapshot.userInfo,
                        focus: .embedding
                    )
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.embedding"),
                        subtitle: L10n.text("ai_settings.row.embedding.subtitle"),
                        icon: "compass.drawing"
                    )
                }

                NavigationLink {
                    AIModelPreferencesView(
                        userInfo: $viewModel.snapshot.userInfo,
                        focus: .voice
                    )
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.voice"),
                        subtitle: L10n.text("ai_settings.row.voice.subtitle"),
                        icon: "waveform"
                    )
                }

                NavigationLink {
                    AIModelPreferencesView(
                        userInfo: $viewModel.snapshot.userInfo,
                        focus: .optimization
                    )
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.optimization"),
                        subtitle: L10n.text("ai_settings.row.optimization.subtitle"),
                        icon: "paintbrush.pointed"
                    )
                }
            }

            Section(L10n.text("ai_settings.section.tools")) {
                NavigationLink {
                    AISearchToolSettingsView(
                        userInfo: $viewModel.snapshot.userInfo,
                        searchKeys: $viewModel.snapshot.searchKeys,
                        toolKeys: $viewModel.snapshot.toolKeys
                    )
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.search_tools"),
                        subtitle: L10n.text("ai_settings.row.search_tools.subtitle"),
                        icon: "wrench.and.screwdriver"
                    )
                }
            }

            Section(L10n.text("ai_settings.section.personalization")) {
                NavigationLink {
                    PromptRepoSettingsView(promptRepo: $viewModel.snapshot.promptRepo)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.prompt_repo"),
                        subtitle: L10n.text("ai_settings.row.prompt_repo.subtitle"),
                        icon: "tray.full"
                    )
                }

                NavigationLink {
                    MemoryArchiveSettingsView(memoryArchive: $viewModel.snapshot.memoryArchive)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.memory_archive"),
                        subtitle: L10n.text("ai_settings.row.memory_archive.subtitle"),
                        icon: "archivebox"
                    )
                }

                NavigationLink {
                    TranslationDicSettingsView(translationDic: $viewModel.snapshot.translationDic)
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Text(L10n.text("ai_settings.save"))
                    }
                }
                .disabled(viewModel.isLoading || viewModel.isSaving || viewModel.hasUnsavedChanges == false)
            }
        }
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
        .alert(L10n.text("ai_settings.saved"), isPresented: Binding(
            get: { viewModel.saveSucceeded },
            set: { presented in
                if presented == false {
                    viewModel.clearSaveFlag()
                }
            }
        )) {
            Button(L10n.text("common.ok")) {}
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
