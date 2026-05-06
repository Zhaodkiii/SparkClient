import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator
    let session: UserSession

    var body: some View {
        List {
            Section(L10n.text("settings.section.account")) {
                NavigationLink {
                    AccountManagementView(viewModel: accountManagementViewModel, session: session)
                        .hidesMainTabBarWhenPushed()
                } label: {
                    HStack {
                        Label(L10n.text("settings.account_management"), systemImage: "person.crop.circle")
                        Spacer()
                        Text(session.displayName.isEmpty ? session.email : session.displayName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section(L10n.text("settings.section.architecture")) {
                Text(L10n.text("settings.architecture.description"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("settings.section.ai")) {
                NavigationLink {
                    AISettingsView(viewModel: aiSettingsViewModel)
                        .hidesMainTabBarWhenPushed()
                } label: {
                    HStack {
                        Label(
                            L10n.text("settings.ai_scenarios"),
                            systemImage: "cpu"
                        )
                        Spacer()
                        Text(L10n.text("settings.ai_scenarios.subtitle"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("版本") {
                HStack {
                    Text("当前版本")
                    Spacer()
                    Text("\(SparkSystemInfo().appVersion) (\(SparkSystemInfo().buildVersion))")
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await versionUpdateCoordinator.manualCheck() }
                } label: {
                    if versionUpdateCoordinator.isCheckingManually {
                        ProgressView()
                    } else {
                        Text("检查更新")
                    }
                }
                .disabled(versionUpdateCoordinator.isCheckingManually)
                if let message = versionUpdateCoordinator.manualCheckMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.text("settings.section.sync")) {
                Toggle(isOn: $viewModel.syncEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("settings.sync.enable"))
                        Text(L10n.text("settings.sync.subtitle"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: viewModel.syncEnabled) { enabled in
                    Task { await viewModel.updateSyncEnabled(enabled) }
                }

                Picker(L10n.text("settings.sync.priority"), selection: $viewModel.syncPriority) {
                    Text(L10n.text("settings.sync.priority.realtime")).tag(CloudSyncPriority.realtime)
                    Text(L10n.text("settings.sync.priority.balanced")).tag(CloudSyncPriority.balanced)
                    Text(L10n.text("settings.sync.priority.background")).tag(CloudSyncPriority.background)
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.syncEnabled == false || viewModel.isSyncing)
                .onChange(of: viewModel.syncPriority) { priority in
                    Task { await viewModel.updateSyncPriority(priority) }
                }

                HStack {
                    Text(L10n.text("settings.sync.last_time"))
                    Spacer()
                    Text(viewModel.lastSyncDescription)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                Button {
                    Task { await viewModel.triggerSyncNow() }
                } label: {
                    if viewModel.isSyncing {
                        ProgressView()
                    } else {
                        Text(L10n.text("settings.sync.now"))
                    }
                }
                .disabled(viewModel.syncEnabled == false || viewModel.isSyncing)
            }

            Section(L10n.text("settings.section.cache")) {
                Button {
                    viewModel.clearETagCache()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("settings.cache.clear_etag"))
                        Text(L10n.text("settings.cache.clear_etag.subtitle"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        }
        .navigationTitle(L10n.text("settings.title"))
        .task {
            await viewModel.loadSyncPreference()
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
