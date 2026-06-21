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
                MemberSetupAccentAddButton(title: "添加症状记录") {
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
        MemberSetupSection(title: "症状筛查") {
            VStack(alignment: .leading, spacing: 14) {
                Text("近期是否有任何身体不适？")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    screeningChoice(
                        title: "无任何不适",
                        isSelected: symptomStatus == .none,
                        action: { symptomStatus = .none }
                    )
                    screeningChoice(
                        title: "有症状",
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
            Text("贴心提示：保持健康是最好的状态，直接点击下方保存即可。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quickUploadCard: some View {
        MemberSetupSection(title: "快速录入") {
            Button {
                showingUploadSheet = true
            } label: {
                VStack(spacing: 10) {
                    Label("拍照 / 上传病历凭证", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)

                    Text("系统将自动解析病历，提取症状与复查随访建议")
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
                MemberSetupSection(title: "已有症状") {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else if viewModel.memberSymptoms.isEmpty == false {
                MemberSetupSection(title: "已有症状") {
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
        medicalDocumentUploadViewModel.prepareAndStart(files: files, kind: .caseDocument)
    }
}
