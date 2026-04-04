import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let session: UserSession

    var body: some View {
        List {
            Section(L10n.text("settings.section.session")) {
                settingsRow(title: L10n.text("settings.email"), value: session.email)
                settingsRow(
                    title: L10n.text("settings.sign_in_method"),
                    value: L10n.text("settings.sign_in_method.apple")
                )
                settingsRow(title: L10n.text("settings.sign_in_time"), value: session.signedInAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section(L10n.text("settings.section.architecture")) {
                Text(L10n.text("settings.architecture.description"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("settings.section.ai")) {
                NavigationLink {
                    AISettingsView(viewModel: aiSettingsViewModel)
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

            Section {
                Button(role: .destructive) {
                    Task { await viewModel.signOut() }
                } label: {
                    if viewModel.isSigningOut {
                        ProgressView()
                    } else {
                        Text(L10n.text("settings.sign_out"))
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

    private func settingsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
