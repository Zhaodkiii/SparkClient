import Combine
import SwiftUI

@MainActor
final class NutritionMealFoodCopyViewModel: ObservableObject {
    @Published var targetDate: Date
    @Published var targetMealType: NutritionMealType
    @Published private(set) var isCopying = false
    @Published private(set) var errorMessageKey: String?

    let items: [NutritionMealFoodEditItemViewData]
    let memberID: Int

    private let mealRecordUseCase: NutritionMealRecordUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let notificationStore: NotificationStore

    init(
        items: [NutritionMealFoodEditItemViewData],
        memberID: Int,
        sourceDate: Date,
        sourceMealType: NutritionMealType?,
        dependencies: NutritionFeatureDependencies
    ) {
        self.items = items
        self.memberID = memberID
        self.targetDate = sourceDate
        self.targetMealType = sourceMealType ?? .lunch
        self.mealRecordUseCase = dependencies.mealRecordUseCase
        self.healthKitSyncUseCase = dependencies.healthKitSyncUseCase
        self.memberContextStore = dependencies.memberContextStore
        self.notificationStore = dependencies.notificationStore
    }

    func setYesterday() {
        targetDate = Calendar.current.date(byAdding: .day, value: -1, to: targetDate) ?? targetDate
    }

    func copy(onSuccess: @escaping () -> Void) async {
        guard isCopying == false, items.isEmpty == false else { return }
        isCopying = true
        errorMessageKey = nil
        defer { isCopying = false }

        do {
            let record = try await mealRecordUseCase.copyMealFoods(
                items: items,
                memberID: memberID,
                targetDate: targetDate,
                targetMealType: targetMealType
            )
            if let member = memberContextStore.context.members.first(where: { $0.id == memberID }) {
                await healthKitSyncUseCase.writeMealRecordIfNeeded(member: member, record: record)
            }
            NotificationCenter.default.post(name: .nutritionMealRecordDidSave, object: nil)
            NutritionNotificationPresenter.presentSuccess(
                store: notificationStore,
                message: L10n.text("nutrition.meal_food.copy.success"),
                source: "nutrition.meal_food.copy"
            )
            onSuccess()
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
            NutritionNotificationPresenter.presentError(
                store: notificationStore,
                messageKey: errorMessageKey ?? "nutrition.error.generic",
                source: "nutrition.meal_food.copy"
            )
        }
    }

    func clearError() {
        errorMessageKey = nil
    }
}

struct NutritionMealFoodCopyView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionMealFoodCopyViewModel

    init(
        items: [NutritionMealFoodEditItemViewData],
        memberID: Int,
        sourceDate: Date,
        sourceMealType: NutritionMealType?,
        dependencies: NutritionFeatureDependencies
    ) {
        _viewModel = StateObject(
            wrappedValue: NutritionMealFoodCopyViewModel(
                items: items,
                memberID: memberID,
                sourceDate: sourceDate,
                sourceMealType: sourceMealType,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        Form {
            Section {
                DatePicker(
                    L10n.text("nutrition.meal_food.copy.target_date"),
                    selection: $viewModel.targetDate,
                    displayedComponents: .date
                )

                Button(L10n.text("nutrition.meal_food.copy.yesterday")) {
                    viewModel.setYesterday()
                }
            }

            Section(L10n.text("nutrition.meal_food.copy.target_meal")) {
                Picker(L10n.text("nutrition.meal_food.copy.target_meal"), selection: $viewModel.targetMealType) {
                    ForEach(NutritionMealType.allCases, id: \.self) { mealType in
                        Text(L10n.text(mealType.localizationKey)).tag(mealType)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                Button {
                    Task {
                        await viewModel.copy {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isCopying {
                            ProgressView()
                        } else {
                            Text(L10n.text("nutrition.meal_food.copy.action"))
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isCopying)
            }
        }
        .navigationTitle(L10n.text("nutrition.meal_food.copy.title"))
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessageKey != nil },
            set: { if $0 == false { viewModel.clearError() } }
        )
    }
}
