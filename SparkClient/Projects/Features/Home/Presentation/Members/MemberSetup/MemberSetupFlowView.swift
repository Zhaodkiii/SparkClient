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
            }
        }
        .sheet(item: $viewModel.activeSheet) { route in
            switch route {
            case .medical:
                MemberMedicalSetupSheetView(
                    member: viewModel.createdMember,
                    medicalQueryAPI: viewModel.homeDependencies.medicalQueryAPI,
                    setupUseCase: viewModel.homeDependencies.memberModuleSetupUseCase,
                    homeDependencies: viewModel.homeDependencies
                ) { summary in
                    Task { await viewModel.markModuleCompleted(.medical, summaryText: summary) }
                }
            case .nutrition:
                MemberNutritionSetupSheetView(
                    member: viewModel.createdMember,
                    goalUseCase: viewModel.homeDependencies.nutritionDependencies.goalUseCase,
                    setupUseCase: viewModel.homeDependencies.memberModuleSetupUseCase
                ) { summary in
                    Task { await viewModel.markModuleCompleted(.nutrition, summaryText: summary) }
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
            await viewModel.loadExistingModuleSettingsIfNeeded()
            await onAppearAction?.call()
        }
    }

    private func pop() {
        guard viewModel.navigationPath.isEmpty == false else { return }
        _ = viewModel.navigationPath.popLast()
    }
}
