import SwiftUI

struct MemberNutritionModuleSummaryView: View {
    @StateObject private var viewModel: MemberNutritionModuleSummaryViewModel
    @ObservedObject var flowViewModel: MemberSetupFlowViewModel
    @Environment(\.dismiss) private var dismiss

    init(member: Member, flowViewModel: MemberSetupFlowViewModel) {
        _viewModel = StateObject(wrappedValue: MemberNutritionModuleSummaryViewModel(member: member, flowViewModel: flowViewModel))
        self.flowViewModel = flowViewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemberModuleSummaryHeaderView(
                    iconName: "fork.knife",
                    iconColor: Color(red: 0.29, green: 0.79, blue: 0.39),
                    title: MemberSetupModule.nutrition.title,
                    subtitle: viewModel.headerSubtitle,
                    completedCount: viewModel.completedCount,
                    totalCount: viewModel.sections.count,
                    emptyHint: "还没有填写饮食资料。可以从基础信息开始逐步完善。"
                )

                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在加载饮食资料")
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
        .navigationTitle(MemberSetupModule.nutrition.title)
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
