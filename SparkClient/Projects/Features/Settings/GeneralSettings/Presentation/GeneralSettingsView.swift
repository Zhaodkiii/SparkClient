import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var versionUpdateCoordinator: AppVersionUpdateCoordinator
    @ObservedObject private var preferencesStore = HomeNutritionEntryPreferencesStore.shared
    @ObservedObject private var medicationPreferencesStore = MedicationReminderPreferencesStore.shared

    var body: some View {
        List {
            versionSection
            homeNutritionEntrySection
            medicalSection
            MedicalExtractionRetrySettingsSection()
            cacheSection
        }
        .navigationTitle(L10n.text("settings.general.title"))
    }

    private var medicalSection: some View {
        Section {
            Toggle(
                L10n.text("settings.general.medical.show_drug_name_in_notification"),
                isOn: $medicationPreferencesStore.showsDrugNameInNotification
            )
        } header: {
            Text(L10n.text("settings.general.medical.section"))
        } footer: {
            Text(L10n.text("settings.general.medical.show_drug_name_in_notification.footer"))
        }
        .onChange(of: medicationPreferencesStore.showsDrugNameInNotification) { _ in
            postMedicationPreferencesChanged()
        }
    }

    private func postMedicationPreferencesChanged() {
        NotificationCenter.default.post(name: .medicationReminderPreferencesChanged, object: nil)
    }

    private var homeNutritionEntrySection: some View {
        Section {
            Picker(
                L10n.text("settings.general.home_nutrition_entry.title"),
                selection: $preferencesStore.displayMode
            ) {
                ForEach(HomeNutritionEntryDisplayMode.allCases) { mode in
                    Text(L10n.text(mode.localizationKey)).tag(mode)
                }
            }
        } footer: {
            Text(L10n.text("settings.general.home_nutrition_entry.footer"))
        }
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
