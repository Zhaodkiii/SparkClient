import Combine
import Foundation

@MainActor
final class NutritionFoodConfirmViewModel: ObservableObject {
    @Published var items: [NutritionFoodSelectionItem]
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessageKey: String?

    let mealType: NutritionMealType
    let memberID: Int
    let date: Date

    private let mealRecordUseCase: NutritionMealRecordUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let logger: Logger

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        mealType: NutritionMealType,
        items: [NutritionFoodSelectionItem]
    ) {
        self.mealRecordUseCase = dependencies.mealRecordUseCase
        self.healthKitSyncUseCase = dependencies.healthKitSyncUseCase
        self.memberContextStore = dependencies.memberContextStore
        self.logger = dependencies.logger
        self.memberID = memberID
        self.date = date
        self.mealType = mealType
        self.items = items
    }

    var overview: NutritionOverviewGridData {
        NutritionDraftBuilder.aggregateOverview(from: items)
    }

    func updateServingRatio(for itemID: UUID, ratio: NutritionServingRatio) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].servingRatio = ratio
    }

    func clearError() {
        errorMessageKey = nil
    }

    func save(onSuccess: @escaping () -> Void) async {
        guard isSaving == false else { return }
        guard items.isEmpty == false else { return }

        isSaving = true
        errorMessageKey = nil
        defer { isSaving = false }

        let request = NutritionDraftBuilder.makeCreateRequest(
            memberID: memberID,
            mealType: mealType,
            date: date,
            items: items
        )

        do {
            let record = try await mealRecordUseCase.createMealRecord(request)
            if let member = memberContextStore.context.members.first(where: { $0.id == memberID }) {
                await healthKitSyncUseCase.writeMealRecordIfNeeded(member: member, record: record)
            }
            NotificationCenter.default.post(name: .nutritionMealRecordDidSave, object: nil)
            onSuccess()
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
            logger.warning(
                "饮食记录保存失败 memberID=\(memberID) error=\(error.localizedDescription)",
                module: .nutrition
            )
        }
    }
}
