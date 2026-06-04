import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator

    var body: some View {
        List {
            versionSection
            MedicalExtractionRetrySettingsSection()
            cacheSection
        }
        .navigationTitle(L10n.text("settings.general.title"))
    }

    private var versionSection: some View {
        Section(L10n.text("settings.section.version")) {
            HStack {
                Text(L10n.text("settings.version.current"))
                Spacer()
                Text("\(SparkSystemInfo.shared.appVersion) (\(SparkSystemInfo.shared.buildVersion))")
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await versionUpdateCoordinator.manualCheck() }
            } label: {
                if versionUpdateCoordinator.isCheckingManually {
                    ProgressView()
                } else {
                    Text(L10n.text("settings.version.check_update"))
                }
            }
            .disabled(versionUpdateCoordinator.isCheckingManually)
            if let message = versionUpdateCoordinator.manualCheckMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cacheSection: some View {
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
}
