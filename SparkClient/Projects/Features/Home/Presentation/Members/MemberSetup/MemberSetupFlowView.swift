import SwiftUI

struct MemberSetupFlowView: View {
    @StateObject private var viewModel: MemberSetupFlowViewModel
    @Environment(\.dismiss) private var dismiss
    let onAppearAction: MainActorAsyncVoidAction?
    let onMemberCreated: ((Member) -> Void)?

    init(
        mode: MemberSetupFlowMode = .create,
        store: MemberContextStore,
        homeDependencies: HomeFeatureDependencies,
        onAppearAction: MainActorAsyncVoidAction? = nil,
        onMemberCreated: ((Member) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: MemberSetupFlowViewModel(mode: mode, store: store, homeDependencies: homeDependencies))
        self.onAppearAction = onAppearAction
        self.onMemberCreated = onMemberCreated
    }

    var body: some View {
        CompatibleRouteNavigationContainer(path: $viewModel.navigationPath, legacyStackStyle: true) {
            MemberNameBirthStepView(
                draft: $viewModel.draft,
                canAdvance: viewModel.canAdvanceFromBasicInfo,
                onNext: { viewModel.navigationPath.append(.relationship) }
            )
        } destination: { route in
            switch route {
            case .relationship:
                MemberRelationshipGenderStepView(
                    draft: $viewModel.draft,
                    canAdvance: viewModel.canAdvanceFromRelationship,
                    isLoading: viewModel.isSavingMember,
                    onBack: { pop() },
                    onNext: {
                        Task {
                            if await viewModel.createMember() {
                                viewModel.navigationPath = [.modules]
                            }
                        }
                    }
                )
            case .modules:
                MemberModuleSetupView(
                    viewModel: viewModel,
                    onDoneAction: MainActorAsyncVoidAction {
                        if await viewModel.finish() {
                            if let member = viewModel.createdMember {
                                onMemberCreated?(member)
                            }
                            dismiss()
                        }
                    },
                    onSkipAction: MainActorAsyncVoidAction {
                        if await viewModel.finish() {
                            if let member = viewModel.createdMember {
                                onMemberCreated?(member)
                            }
                            dismiss()
                        }
                    }
                )
            case .medicalSummary:
                if let member = viewModel.createdMember {
                    MemberMedicalModuleSummaryView(member: member, flowViewModel: viewModel)
                } else {
                    Text("成员信息缺失")
                        .foregroundStyle(.secondary)
                }
            case .nutritionSummary:
                if let member = viewModel.createdMember {
                    MemberNutritionModuleSummaryView(member: member, flowViewModel: viewModel)
                } else {
                    Text("成员信息缺失")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: $viewModel.activeSheet) { route in
            switch route {
            case .medical(let entryMode):
                MemberMedicalSetupSheetView(
                    member: viewModel.createdMember,
                    medicalQueryAPI: viewModel.homeDependencies.medicalQueryAPI,
                    setupUseCase: viewModel.homeDependencies.memberModuleSetupUseCase,
                    homeDependencies: viewModel.homeDependencies,
                    preloadedCompleteData: viewModel.moduleSetupCache(for: viewModel.createdMember?.id ?? -1)?.completeData,
                    preloadedNutritionGoalState: viewModel.moduleSetupCache(for: viewModel.createdMember?.id ?? -1)?.completeData?.nutritionGoalState
                        ?? viewModel.moduleSetupCache(for: viewModel.createdMember?.id ?? -1)?.nutritionGoalState,
                    onCompleteDataPatch: viewModel.patchCompleteData,
                    entryMode: entryMode
                ) { summary in
                    Task {
                        if entryMode == .full {
                            await viewModel.markModuleCompleted(.medical, summaryText: summary)
                        }
                    }
                } onSectionCompleted: { mode, summary in
                    Task {
                        if let sectionCode = mode.sectionCode {
                            await viewModel.markSectionCompleted(.medical, sectionCode: sectionCode, summaryText: summary)
                        }
                    }
                }
            case .nutrition(let entryMode):
                MemberNutritionSetupSheetView(
                    member: viewModel.createdMember,
                    goalUseCase: viewModel.homeDependencies.nutritionDependencies.goalUseCase,
                    setupUseCase: viewModel.homeDependencies.memberModuleSetupUseCase,
                    entryMode: entryMode
                ) { summary in
                    Task {
                        if entryMode == .full {
                            await viewModel.markModuleCompleted(.nutrition, summaryText: summary)
                        }
                    }
                } onSectionCompleted: { mode, summary in
                    Task {
                        if let sectionCode = mode.sectionCode {
                            await viewModel.markSectionCompleted(.nutrition, sectionCode: sectionCode, summaryText: summary)
                        }
                    }
                }
            case .lifestyle:
                MemberLifestyleSetupSheetView(
                    onCompletedAction: MainActorAsyncVoidAction {
                        await viewModel.markModuleCompleted(.dailyHealth, summaryText: "日常健康模块预留")
                    }
                )
            }
        }
        .alert(
            L10n.text("common.ok"),
            isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            )
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {
                viewModel.alertMessage = nil
            }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .task {
            await viewModel.preloadModuleSetupCacheIfNeeded()
            await viewModel.loadExistingModuleSettingsIfNeeded()
            await onAppearAction?.call()
        }
    }

    private func pop() {
        guard viewModel.navigationPath.isEmpty == false else { return }
        _ = viewModel.navigationPath.popLast()
    }
}
