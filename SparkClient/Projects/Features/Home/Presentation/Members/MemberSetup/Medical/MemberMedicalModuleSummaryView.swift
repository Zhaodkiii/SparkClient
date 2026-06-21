import SwiftUI

struct MemberMedicalModuleSummaryView: View {
    @StateObject private var viewModel: MemberMedicalModuleSummaryViewModel
    @ObservedObject var flowViewModel: MemberSetupFlowViewModel
    @Environment(\.dismiss) private var dismiss

    init(member: Member, flowViewModel: MemberSetupFlowViewModel) {
        _viewModel = StateObject(wrappedValue: MemberMedicalModuleSummaryViewModel(member: member, flowViewModel: flowViewModel))
        self.flowViewModel = flowViewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemberModuleSummaryHeaderView(
                    iconName: "heart.fill",
                    iconColor: Color(red: 1.0, green: 0.33, blue: 0.38),
                    title: MemberSetupModule.medical.title,
                    subtitle: viewModel.headerSubtitle,
                    completedCount: viewModel.completedCount,
                    totalCount: viewModel.sections.count,
                    emptyHint: "还没有填写医疗资料。可以从任意一组开始，也可以直接使用「开始全部流程」一次性完成。"
                )

                MemberModuleStartAllCard(
                    title: "开始全部流程",
                    subtitle: "基础档案 -> 病史 -> 生活习惯 -> 体检档案 -> 风险评估"
                ) {
                    viewModel.openFullFlow()
                }

                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在加载医疗资料")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(viewModel.sections) { section in
                        MemberModuleSectionCard(section: section) {
                            viewModel.openSection(section)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(MemberSetupModule.medical.title)
        .navigationBarTitleDisplayMode(.inline)
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.done", fallback: "完成"),
            primaryEnabled: true,
            isLoading: viewModel.isPersisting,
            onPrimary: {
                Task {
                    viewModel.isPersisting = true
                    await viewModel.finishModule()
                    viewModel.isPersisting = false
                    popToModules()
                }
            },
            secondaryTitle: "暂不填写",
            onSecondary: {
                Task {
                    viewModel.isPersisting = true
                    await viewModel.skipModule()
                    viewModel.isPersisting = false
                    popToModules()
                }
            }
        )
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: flowViewModel.activeSheet) { newValue in
            if newValue == nil {
                Task { await viewModel.loadIfNeeded() }
            }
        }
    }

    private func popToModules() {
        if let index = flowViewModel.navigationPath.lastIndex(of: .modules) {
            flowViewModel.navigationPath = Array(flowViewModel.navigationPath.prefix(index + 1))
        } else {
            flowViewModel.navigationPath = [.modules]
        }
    }
}
