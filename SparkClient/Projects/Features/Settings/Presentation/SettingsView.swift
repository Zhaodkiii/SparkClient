import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator
    let session: UserSession
    let onAccountEntryTap: () -> Void

    var body: some View {
        List {
            Section(L10n.text("settings.section.account")) {
                Button(action: onAccountEntryTap) {
                    HStack {
                        Label(L10n.text("settings.account_management"), systemImage: "person.crop.circle")
                        Spacer()
                        Text(accountTrailingText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityHint(
                    session.isDeviceAccount
                        ? L10n.text("settings.account.device_not_linked.accessibility_hint")
                        : L10n.text("settings.account_management")
                )
            }

            Section(L10n.text("settings.section.ai")) {
                MainNavigationLink {
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

            Section {
                MainNavigationLink {
                    GeneralSettingsView(
                        viewModel: viewModel,
                        versionUpdateCoordinator: versionUpdateCoordinator
                    )
                } label: {
                    HStack {
                        Label(
                            L10n.text("settings.general.entry"),
                            systemImage: "slider.horizontal.3"
                        )
                        Spacer()
                        Text(L10n.text("settings.general.subtitle"))
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

    private var accountTrailingText: String {
        if session.isDeviceAccount {
            return L10n.text("settings.account.device_not_linked")
        }
        if session.displayName.isEmpty == false {
            return session.displayName
        }
        return session.email
    }
}
