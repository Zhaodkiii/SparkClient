import SwiftUI

struct MemberModuleSetupView: View {
    @ObservedObject var viewModel: MemberSetupFlowViewModel
    let onDoneAction: MainActorAsyncVoidAction
    let onSkipAction: MainActorAsyncVoidAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MemberSetupStepHeaderView(
                    title: L10n.text("member.module.selection.title", fallback: "选择维护模块"),
                    subtitle: L10n.text("member.module.selection.subtitle", fallback: "至少开启一个模块，后续可以分步完善"),
                    step: 3,
                    total: 3
                )

                if let member = viewModel.createdMember {
                    MemberSetupSummaryView(
                        member: member,
                        selectedCount: viewModel.selectedModules.filter(\.isVisibleInSetup).count,
                        completedCount: viewModel.completedModules.filter(\.isVisibleInSetup).count
                    )
                }

                if viewModel.isLoadingExistingModules {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.text("member.module.selection.loading", fallback: "正在读取已开通模块"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }

                VStack(spacing: 22) {
                    ForEach(MemberSetupModule.allCases.filter(\.isVisibleInSetup)) { module in
                        MemberModuleToggleRow(
                            module: module,
                            isSelected: viewModel.selectedModules.contains(module),
                            onOpen: {
                                viewModel.openSheet(for: module)
                            }
                        )
                    }
                }

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .padding(.bottom, 120)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("member.module.selection.title", fallback: "选择维护模块"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .memberSetupBottomBar(
            primaryTitle: L10n.text("common.done", fallback: "完成"),
            primaryEnabled: viewModel.canFinish,
            isLoading: viewModel.isPersistingModules,
            onPrimary: {
                Task { await onDoneAction.call() }
            },
            secondaryTitle: L10n.text("member.module.selection.skip", fallback: "暂不完善"),
            onSecondary: {
                Task { await onSkipAction.call() }
            }
        )
        .disabled(viewModel.isLoadingExistingModules)
    }
}
