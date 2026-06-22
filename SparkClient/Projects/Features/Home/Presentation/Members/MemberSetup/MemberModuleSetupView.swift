import SwiftUI

struct MemberModuleSetupView: View {
    @ObservedObject var viewModel: MemberSetupFlowViewModel
    let onDoneAction: MainActorAsyncVoidAction
    let onSkipAction: MainActorAsyncVoidAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemberSetupHeroView(
                    systemImage: "heart.text.square.fill",
                    accentColor: .systemOrange
                )

                if let member = viewModel.createdMember {
                    MemberSetupStepperCard(
                        title: L10n.text("home.members.field.basic_info", fallback: "基本信息"),
                        systemImage: "person.text.rectangle"
                    ) {
                        memberSummaryRow(member: member)
                    }
                }

                
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.title2.weight(.bold))
                            .imageScale(.medium)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                        Text(L10n.text("member.module.selection.title", fallback: "选择维护模块"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    Text(L10n.text("member.module.selection.subtitle", fallback: "至少开启一个模块，后续可以分步完善"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 16) {
                        if viewModel.isLoadingExistingModules {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(L10n.text("member.module.selection.loading", fallback: "正在读取已开通模块"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }else {
                            
                            ForEach(MemberSetupModule.allCases.filter(\.isVisibleInSetup)) { module in
                                MemberModuleToggleRow(
                                    module: module,
                                    selectionStatus: .init(
                                        isSelected: viewModel.selectedModules.contains(module),
                                        isCompleted: viewModel.completedModules.contains(module)
                                    ),
                                    onOpen: {
                                        viewModel.openModuleSummary(for: module)
                                    }
                                )
                            }
                        }

                    }
//                    .padding(20)
//                    .background(
//                        RoundedRectangle(cornerRadius: 16, style: .continuous)
//                            .fill(Color(uiColor: .systemBackground))
//                    )
//                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
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
        .disabled(viewModel.isLoadingExistingModules || viewModel.isPreloadingModuleCache)
    }

    private func memberSummaryRow(member: Member) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(Color(uiColor: .systemBlue))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.headline.weight(.semibold))
                Text(MemberRelationshipCatalog.displayTitle(for: member.relationship))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            MemberModuleCompletionBadge(
                isCompleted: viewModel.completedModules.filter(\.isVisibleInSetup).count
                    == viewModel.selectedModules.filter(\.isVisibleInSetup).count
                    && viewModel.selectedModules.filter(\.isVisibleInSetup).isEmpty == false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
