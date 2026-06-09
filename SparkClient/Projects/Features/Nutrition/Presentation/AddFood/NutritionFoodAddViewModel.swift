import Combine
import Foundation

enum NutritionFoodAddCover: Identifiable {
    case search(mode: NutritionFoodSearchMode, initialQuery: String)
    case barcodeScanner
    case cameraFlow
    case naturalLanguageInput
    case selectionPreview

    var id: String {
        switch self {
        case .search(let mode, let initialQuery):
            return "search:\(mode):\(initialQuery)"
        case .barcodeScanner:
            return "barcodeScanner"
        case .cameraFlow:
            return "cameraFlow"
        case .naturalLanguageInput:
            return "naturalLanguageInput"
        case .selectionPreview:
            return "selectionPreview"
        }
    }
}

struct NutritionFoodDetailAddContext: Identifiable, Equatable {
    let id = UUID()
    let searchResult: NutritionFoodSearchResultViewData
    let editingItemID: UUID?
    let initialServingRatio: NutritionServingRatio
    let initialQuantity: Double
}

@MainActor
final class NutritionFoodAddViewModel: ObservableObject {
    @Published private(set) var recommendedFoods: [NutritionFoodSearchResultViewData] = []
    @Published private(set) var isLoadingRecommended = false
    @Published private(set) var recommendedErrorKey: String?
    @Published var selectionItems: [NutritionFoodSelectionItem] = []
    @Published var contentFilter: NutritionFoodAddContentFilter = .food
    @Published var presentedCover: NutritionFoodAddCover?
    @Published var detailAddContext: NutritionFoodDetailAddContext?
    @Published private(set) var isSaving = false
    @Published private(set) var saveErrorMessageKey: String?

    let mealType: NutritionMealType
    let memberID: Int
    let date: Date

    private let searchUseCase: NutritionSearchUseCase
    private let mealRecordUseCase: NutritionMealRecordUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let notificationStore: NotificationStore
    private let logger: Logger

    init(
        memberID: Int,
        date: Date,
        mealType: NutritionMealType,
        searchUseCase: NutritionSearchUseCase,
        mealRecordUseCase: NutritionMealRecordUseCase,
        healthKitSyncUseCase: NutritionHealthKitSyncUseCase,
        memberContextStore: MemberContextStore,
        notificationStore: NotificationStore,
        logger: Logger
    ) {
        self.memberID = memberID
        self.date = date
        self.mealType = mealType
        self.searchUseCase = searchUseCase
        self.mealRecordUseCase = mealRecordUseCase
        self.healthKitSyncUseCase = healthKitSyncUseCase
        self.memberContextStore = memberContextStore
        self.notificationStore = notificationStore
        self.logger = logger
    }

    var selectionCount: Int { selectionItems.count }

    var selectionBadgeText: String {
        selectionCount == 0 ? "⓪" : "\(selectionCount)"
    }

    var canFinish: Bool { selectionItems.isEmpty == false && isSaving == false }

    var searchPlaceholderKey: String {
        switch mealType {
        case .breakfast: return "nutrition.add.search_placeholder.breakfast"
        case .lunch: return "nutrition.add.search_placeholder.lunch"
        case .dinner: return "nutrition.add.search_placeholder.dinner"
        case .snack: return "nutrition.add.search_placeholder.snack"
        }
    }

    func loadRecommendedIfNeeded() async {
        guard recommendedFoods.isEmpty, isLoadingRecommended == false else { return }
        await reloadRecommended()
    }

    func reloadRecommended() async {
        isLoadingRecommended = true
        recommendedErrorKey = nil
        defer { isLoadingRecommended = false }

        let filters = NutritionFoodSearchFilterState(
            mode: .text,
            query: "",
            type: contentFilter.searchType,
            favoriteOnly: false,
            createdByMeOnly: contentFilter.createdByMeOnly
        )

        do {
            recommendedFoods = try await searchUseCase.search(memberID: memberID, filters: filters)
        } catch {
            recommendedFoods = []
            let messageKey = NutritionErrorMapper.messageKey(for: error)
            recommendedErrorKey = messageKey
            NutritionNotificationPresenter.presentError(
                store: notificationStore,
                messageKey: messageKey,
                source: "nutrition.food_add.recommended"
            )
        }
    }

    func contentFilterChanged() {
        recommendedFoods = []
        Task { await reloadRecommended() }
    }

    func addSelection(_ result: NutritionFoodSearchResultViewData) {
        selectionItems.append(NutritionFoodSelectionItem(searchResult: result))
    }

    func removeSelection(id: UUID) {
        selectionItems.removeAll { $0.id == id }
    }

    func updateSelection(
        id: UUID,
        servingRatio: NutritionServingRatio,
        quantity: Double
    ) {
        guard let index = selectionItems.firstIndex(where: { $0.id == id }) else { return }
        selectionItems[index].servingRatio = servingRatio
        selectionItems[index].quantity = quantity
    }

    func openDetailAdd(for result: NutritionFoodSearchResultViewData, editingItemID: UUID? = nil) {
        if let editingItemID,
           let item = selectionItems.first(where: { $0.id == editingItemID }) {
            detailAddContext = NutritionFoodDetailAddContext(
                searchResult: item.searchResult,
                editingItemID: editingItemID,
                initialServingRatio: item.servingRatio,
                initialQuantity: item.quantity
            )
        } else {
            detailAddContext = NutritionFoodDetailAddContext(
                searchResult: result,
                editingItemID: nil,
                initialServingRatio: .full,
                initialQuantity: 1
            )
        }
    }

    func commitDetailAdd(servingRatio: NutritionServingRatio, quantity: Double) {
        guard let context = detailAddContext else { return }

        if let editingItemID = context.editingItemID {
            updateSelection(id: editingItemID, servingRatio: servingRatio, quantity: quantity)
        } else {
            selectionItems.append(
                NutritionFoodSelectionItem(
                    searchResult: context.searchResult,
                    servingRatio: servingRatio,
                    quantity: quantity
                )
            )
        }
        detailAddContext = nil
    }

    func openSelectionPreview() {
        presentedCover = .selectionPreview
    }

    func clearSaveError() {
        saveErrorMessageKey = nil
    }

    func save(onSuccess: @escaping () -> Void) async {
        guard isSaving == false else { return }
        guard selectionItems.isEmpty == false else { return }

        isSaving = true
        saveErrorMessageKey = nil
        defer { isSaving = false }

        do {
            let record = try await mealRecordUseCase.createMealRecord(
                memberID: memberID,
                mealType: mealType,
                date: date,
                items: selectionItems
            )
            if let member = memberContextStore.context.members.first(where: { $0.id == memberID }) {
                await healthKitSyncUseCase.writeMealRecordIfNeeded(member: member, record: record)
            }
            NotificationCenter.default.post(name: .nutritionMealRecordDidSave, object: nil)
            onSuccess()
        } catch {
            saveErrorMessageKey = NutritionErrorMapper.messageKey(for: error)
            NutritionNotificationPresenter.presentError(
                store: notificationStore,
                messageKey: saveErrorMessageKey ?? "nutrition.error.generic",
                source: "nutrition.food_add.save"
            )
            logger.warning(
                "饮食记录保存失败 memberID=\(memberID) error=\(error.localizedDescription)",
                module: .nutrition
            )
        }
    }

    func openTextSearch() {
        presentedCover = .search(mode: .text, initialQuery: "")
    }

    func openSearchField() {
        openTextSearch()
    }

    func openBarcodeFlow() {
        presentedCover = .barcodeScanner
    }

    func handleBarcodeScanned(_ barcode: String) {
        presentedCover = .search(mode: .barcode, initialQuery: barcode)
    }
}
