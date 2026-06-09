import Combine
import SwiftUI

@MainActor
final class NutritionMealFoodDetailEditViewModel: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessageKey: String?

    let row: NutritionMealFoodRowViewData
    let mealType: NutritionMealType
    let record: SparkNutritionAPI.RemoteMealRecord

    private let mealRecordUseCase: NutritionMealRecordUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let memberID: Int
    private let notificationStore: NotificationStore

    init(
        row: NutritionMealFoodRowViewData,
        mealType: NutritionMealType,
        record: SparkNutritionAPI.RemoteMealRecord,
        dependencies: NutritionFeatureDependencies,
        memberID: Int
    ) {
        self.row = row
        self.mealType = mealType
        self.record = record
        self.memberID = memberID
        self.mealRecordUseCase = dependencies.mealRecordUseCase
        self.healthKitSyncUseCase = dependencies.healthKitSyncUseCase
        self.memberContextStore = dependencies.memberContextStore
        self.notificationStore = dependencies.notificationStore
    }

    var detailContext: NutritionFoodDetailAddContext {
        let ratio = NutritionServingRatio.closest(to: row.servingRatio)
        let quantity = ratio.rawValue > 0 ? row.servingRatio / ratio.rawValue : 1
        return NutritionFoodDetailAddContext(
            searchResult: NutritionViewDataMapper.searchResult(from: row),
            editingItemID: nil,
            initialServingRatio: ratio,
            initialQuantity: max(quantity, 0.25)
        )
    }

    func save(servingRatio: NutritionServingRatio, quantity: Double, onSuccess: @escaping () -> Void) async {
        guard isSaving == false else { return }
        isSaving = true
        errorMessageKey = nil
        defer { isSaving = false }

        do {
            let updated = try await mealRecordUseCase.updateMealFoodServing(
                record: record,
                mealFoodID: row.mealFoodID,
                servingRatio: servingRatio,
                quantity: quantity
            )
            if let member = memberContextStore.context.members.first(where: { $0.id == memberID }) {
                await healthKitSyncUseCase.writeMealRecordIfNeeded(member: member, record: updated)
            }
            NotificationCenter.default.post(name: .nutritionMealRecordDidSave, object: nil)
            onSuccess()
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
            NutritionNotificationPresenter.presentError(
                store: notificationStore,
                messageKey: errorMessageKey ?? "nutrition.error.generic",
                source: "nutrition.meal_food.save"
            )
        }
    }

    func clearError() {
        errorMessageKey = nil
    }
}

struct NutritionMealFoodDetailEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionMealFoodDetailEditViewModel
    private let dependencies: NutritionFeatureDependencies

    init(
        row: NutritionMealFoodRowViewData,
        record: SparkNutritionAPI.RemoteMealRecord,
        mealType: NutritionMealType,
        dependencies: NutritionFeatureDependencies,
        memberID: Int
    ) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: NutritionMealFoodDetailEditViewModel(
                row: row,
                mealType: mealType,
                record: record,
                dependencies: dependencies,
                memberID: memberID
            )
        )
    }

    var body: some View {
        NutritionFoodDetailAddView(
            context: viewModel.detailContext,
            mealType: viewModel.mealType,
            searchUseCase: dependencies.searchUseCase,
            notificationStore: dependencies.notificationStore,
            primaryButtonKey: "nutrition.detail_add.save",
            embedsNavigation: false,
            dismissOnPrimaryAction: false,
            isSaving: viewModel.isSaving
        ) { servingRatio, quantity in
            Task {
                await viewModel.save(servingRatio: servingRatio, quantity: quantity) {
                    dismiss()
                }
            }
        }
        .navigationBarBackButtonHidden(false)
        .alert(
            L10n.text("nutrition.confirm.save_failed.title"),
            isPresented: errorAlertBinding
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            if let key = viewModel.errorMessageKey {
                Text(L10n.text(key))
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.row.hasAppleHealthLinkedRecord {
                Text(L10n.text("nutrition.apple_health.edit_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessageKey != nil },
            set: { if $0 == false { viewModel.clearError() } }
        )
    }
}
