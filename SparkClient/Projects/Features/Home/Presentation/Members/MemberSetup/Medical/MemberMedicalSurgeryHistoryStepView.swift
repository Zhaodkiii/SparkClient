import SwiftUI

struct MemberMedicalSurgeryHistoryStepView: View {
    @ObservedObject var viewModel: MemberMedicalSetupViewModel
    @Binding var surgeryStatus: MedicalGuideDisclosureStatus

    @State private var showingSurgeryFormSheet = false
    @State private var selectedSurgery: SparkMedicalSyncAPI.RemoteSurgery?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            surgeryScreeningCard

            if surgeryStatus == .none {
                friendlyTipRow
            }

            if surgeryStatus == .have {
                existingSurgeriesSection
                MemberSetupAccentAddButton(title: "添加手术记录") {
                    showingSurgeryFormSheet = true
                }
            }
        }
        .sheet(isPresented: $showingSurgeryFormSheet) {
            CompatibleNavigationContainer {
                SurgeryFormView(
                    mode: .create(
                        .init(
                            memberID: viewModel.member?.id ?? 0,
                            medicalCaseID: nil,
                            submissionService: MedicalRecordFormSubmissionService(
                                workflowAPI: viewModel.medicalWorkflowAPI
                            ),
                            onMutation: { viewModel.applySurgeryMutation($0) }
                        )
                    )
                )
            }
        }
        .sheet(item: $selectedSurgery) { surgery in
            CompatibleNavigationContainer {
                SurgeryDetailView(
                    surgery: surgery,
                    memberID: viewModel.member?.id ?? surgery.member,
                    workflowAPI: viewModel.medicalWorkflowAPI,
                    onUpdated: { viewModel.applySurgeryMutation($0) },
                    onDeleted: { _, response in
                        viewModel.applySurgeryMutation(response, removedSurgeryID: surgery.id)
                    }
                )
            }
        }
        .task {
            await viewModel.refreshMemberSurgeriesIfNeeded()
        }
        .onChange(of: surgeryStatus) { newValue in
            if newValue == .have {
                Task { await viewModel.refreshMemberSurgeriesIfNeeded(force: true) }
            }
        }
    }

    private var surgeryScreeningCard: some View {
        MemberSetupSection(title: "手术情况筛查") {
            VStack(alignment: .leading, spacing: 14) {
                Text("您过往是否曾接受过任何手术治疗（包含微创手术）？")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    screeningChoice(
                        title: "无手术史",
                        isSelected: surgeryStatus == .none,
                        action: { surgeryStatus = .none }
                    )
                    screeningChoice(
                        title: "有手术史",
                        isSelected: surgeryStatus == .have,
                        action: { surgeryStatus = .have }
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
            Text("如果没有相关手术经历，请直接点击下方保存即可。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var existingSurgeriesSection: some View {
        Group {
            if viewModel.isLoadingMemberSurgeries {
                MemberSetupSection(title: "已有手术记录") {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else if viewModel.memberSurgeries.isEmpty == false {
                MemberSetupSection(title: "已有手术记录") {
                    VStack(spacing: 10) {
                        ForEach(viewModel.memberSurgeries) { surgery in
                            Button {
                                selectedSurgery = surgery
                            } label: {
                                memberSurgeryCard(surgery)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func memberSurgeryCard(_ surgery: SparkMedicalSyncAPI.RemoteSurgery) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(SurgeryFormSupport.summaryLine(for: surgery))
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
}
