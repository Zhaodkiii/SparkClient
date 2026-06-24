import SwiftUI

struct MemberMedicalSymptomFollowUpStepView: View {
    @ObservedObject var viewModel: MemberMedicalSetupViewModel
    @Binding var symptomStatus: MedicalGuideDisclosureStatus

    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel

    @State private var showingUploadSheet = false
    @State private var showingSymptomFormSheet = false
    @State private var selectedSymptom: SparkMedicalSyncAPI.RemoteSymptom?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            symptomScreeningCard

            if symptomStatus == .none {
                friendlyTipRow
            }

            if symptomStatus == .have {
//                quickUploadCard
                existingSymptomsSection
                MemberSetupAccentAddButton(title: L10n.text("member.setup.medical.symptom.c8a51c")) {
                    showingSymptomFormSheet = true
                }
            }
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentType: .caseDocument, onConfirm: startCaseDocumentRecognition)
        }
        .sheet(isPresented: $showingSymptomFormSheet) {
            CompatibleNavigationContainer {
                SymptomFormView(
                    mode: .create(
                        .init(
                            memberID: viewModel.member?.id ?? 0,
                            medicalCaseID: nil,
                            submissionService: MedicalRecordFormSubmissionService(
                                workflowAPI: viewModel.medicalWorkflowAPI
                            ),
                            onMutation: { viewModel.applySymptomMutation($0) }
                        )
                    )
                )
            }
        }
        .sheet(item: $selectedSymptom) { symptom in
            CompatibleNavigationContainer {
                SymptomDetailView(
                    symptom: symptom,
                    memberID: viewModel.member?.id ?? symptom.member,
                    workflowAPI: viewModel.medicalWorkflowAPI,
                    onUpdated: { viewModel.applySymptomMutation($0) },
                    onDeleted: { symptomID, response in
                        viewModel.applySymptomMutation(response, removedSymptomID: symptomID)
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(
                    viewModel: medicalDocumentUploadViewModel,
                    aiSettingsViewModel: aiSettingsViewModel
                )
            }
        }
        .task {
            await viewModel.refreshMemberSymptomsIfNeeded()
        }
        .onChange(of: symptomStatus) { newValue in
            if newValue == .none {
                viewModel.clearSymptomFollowUpDraft()
            } else if newValue == .have {
                Task { await viewModel.refreshMemberSymptomsIfNeeded(force: true) }
            }
        }
    }

    private var symptomScreeningCard: some View {
        MemberSetupSection(title: L10n.text("member.setup.medical.symptom.6cb2f5")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("member.setup.medical.symptom.8edac7"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    screeningChoice(
                        title: L10n.text("member.setup.medical.symptom.3d9476"),
                        isSelected: symptomStatus == .none,
                        action: { symptomStatus = .none }
                    )
                    screeningChoice(
                        title: L10n.text("member.setup.medical.symptom.dc316b"),
                        isSelected: symptomStatus == .have,
                        action: { symptomStatus = .have }
                    )
                }
            }
        }
    }

    private var friendlyTipRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(L10n.text("member.setup.medical.symptom.0a337b"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quickUploadCard: some View {
        MemberSetupSection(title: L10n.text("member.setup.medical.chronic.chronic.d6c422")) {
            Button {
                showingUploadSheet = true
            } label: {
                VStack(spacing: 10) {
                    Label(L10n.text("member.setup.medical.symptom.a851ac"), systemImage: "camera.viewfinder")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)

                    Text(L10n.text("member.setup.medical.symptom.b4ff8d"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var existingSymptomsSection: some View {
        Group {
            if viewModel.isLoadingMemberSymptoms {
                MemberSetupSection(title: L10n.text("member.setup.medical.symptom.ae3b5e")) {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else if viewModel.memberSymptoms.isEmpty == false {
                MemberSetupSection(title: L10n.text("member.setup.medical.symptom.ae3b5e")) {
                    VStack(spacing: 10) {
                        ForEach(viewModel.memberSymptoms, id: \.id) { symptom in
                            Button {
                                selectedSymptom = symptom
                            } label: {
                                memberSymptomCard(symptom)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func memberSymptomCard(_ symptom: SparkMedicalSyncAPI.RemoteSymptom) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(SymptomFormSupport.summaryLine(for: symptom))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    private func screeningChoice(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func startCaseDocumentRecognition(files: [MedicalUploadLocalFile]) {
        showingUploadSheet = false
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .caseDocument, member: viewModel.member)
    }
}
