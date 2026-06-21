import SwiftUI

struct MedicalGuideChronicConditionDetail: Equatable, Codable, Sendable {
    var diagnosedYear: String = ""
    var controlStatus: String = ""
    var notes: String = ""
}

struct MemberMedicalChronicConditionStepView: View {
    @Binding var status: MedicalGuideDisclosureStatus
    @Binding var chronicConditions: [String]
    @Binding var conditionDetails: [String: MedicalGuideChronicConditionDetail]

    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel

    @State private var showingUploadSheet = false
    @State private var showingManualEntrySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            diseaseScreeningCard

            if status == .none {
                friendlyTipRow
            }

            if status == .have {
//                quickUploadCard
                existingConditionsSection
                MemberSetupAccentAddButton(title: "添加既往疾病") {
                    showingManualEntrySheet = true
                }
            }
        }
        .sheet(isPresented: $showingUploadSheet) {
            MedicalAttachmentUploadListSheet(documentType: .caseDocument, onConfirm: startCaseDocumentRecognition)
        }
        .sheet(isPresented: $showingManualEntrySheet) {
            CompatibleNavigationContainer {
                ChronicConditionFormView(
                    initial: ChronicConditionFormDraft(
                        conditions: chronicConditions,
                        details: conditionDetails
                    ),
                    onSubmit: { draft in
                        chronicConditions = draft.conditions
                        conditionDetails = draft.details
                        if draft.conditions.isEmpty == false {
                            status = .have
                        }
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
        .onChange(of: status) { newValue in
            if newValue == .none {
                chronicConditions.removeAll()
                conditionDetails.removeAll()
            }
        }
    }

    private var diseaseScreeningCard: some View {
        MemberSetupSection(title: "疾病筛查") {
            VStack(alignment: .leading, spacing: 14) {
                Text("是否曾被确诊过任何慢性疾病或重大疾病？")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    screeningChoice(
                        title: "无既往病史",
                        isSelected: status == .none,
                        action: { status = .none }
                    )
                    screeningChoice(
                        title: "有既往病史",
                        isSelected: status == .have,
                        action: { status = .have }
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
            Text("贴心提示：如果没有相关病史，请直接点击下方保存即可。")
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
                    Label("拍照 / 上传门诊病历或出院小结", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .multilineTextAlignment(.center)

                    Text("系统将自动解析医学术语，提取确诊疾病与关键指标")
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

    private var existingConditionsSection: some View {
        Group {
            if chronicConditions.isEmpty == false {
                MemberSetupSection(title: "已有既往疾病") {
                    VStack(spacing: 10) {
                        ForEach(chronicConditions, id: \.self) { disease in
                            Button {
                                showingManualEntrySheet = true
                            } label: {
                                chronicConditionCard(disease)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func chronicConditionCard(_ disease: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(
                ChronicConditionFormSupport.summaryLine(
                    name: disease,
                    detail: conditionDetails[disease]
                )
            )
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
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
