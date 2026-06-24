import SwiftUI

struct MemberNutritionModuleSummaryView: View {
    @StateObject private var viewModel: MemberNutritionModuleSummaryViewModel
    @ObservedObject var flowViewModel: MemberSetupFlowViewModel
    let onPopToParent: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(
        member: Member,
        flowViewModel: MemberSetupFlowViewModel,
        onPopToParent: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: MemberNutritionModuleSummaryViewModel(member: member, flowViewModel: flowViewModel))
        self.flowViewModel = flowViewModel
        self.onPopToParent = onPopToParent
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
                    emptyHint: L10n.text("member.setup.nutrition.nutrition.0e8892")
                )

                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.text("member.setup.nutrition.nutrition.0b5baa"))
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
                    popBack()
                }
            },
            secondaryTitle: L10n.text("member.setup.medical.nutrition.2e16ac"),
            onSecondary: {
                Task {
                    viewModel.isPersisting = true
                    await viewModel.skipModule()
                    viewModel.isPersisting = false
                    popBack()
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

    private func popBack() {
        if let onPopToParent {
            onPopToParent()
        } else {
            popToModules()
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
