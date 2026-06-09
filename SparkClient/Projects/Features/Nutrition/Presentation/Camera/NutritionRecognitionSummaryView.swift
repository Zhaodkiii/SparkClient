import Combine
import SwiftUI
import UIKit

@MainActor
final class NutritionRecognitionSummaryViewModel: ObservableObject {
    @Published var recognition: NutritionRecognitionResult
    @Published private(set) var itemRatios: [String: NutritionServingRatio] = [:]
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessageKey: String?

    private let dependencies: NutritionFeatureDependencies
    private let memberID: Int
    private let date: Date
    private let mealType: NutritionMealType

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        mealType: NutritionMealType,
        recognition: NutritionRecognitionResult
    ) {
        self.dependencies = dependencies
        self.memberID = memberID
        self.date = date
        self.mealType = mealType
        self.recognition = recognition
        for item in recognition.draft.items {
            itemRatios[item.name] = NutritionServingRatio.closest(to: item.servingRatio)
        }
    }

    var overview: NutritionOverviewGridData {
        var total = NutritionOverviewGridData(energyKcal: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
        for item in recognition.draft.items {
            let ratio = itemRatios[item.name]?.rawValue ?? item.servingRatio
            let itemOverview = estimateItemOverview(item: item, ratio: ratio)
            total.energyKcal += itemOverview.energyKcal
            total.proteinGrams += itemOverview.proteinGrams
            total.carbohydrateGrams += itemOverview.carbohydrateGrams
            total.fatGrams += itemOverview.fatGrams
        }
        if total.energyKcal > 0 {
            return total
        }
        return NutritionOverviewGridData(
            energyKcal: recognition.draft.overview.energyKcal,
            proteinGrams: recognition.draft.overview.proteinG,
            carbohydrateGrams: recognition.draft.overview.carbohydrateG,
            fatGrams: recognition.draft.overview.fatG
        )
    }

    func binding(for itemName: String) -> Binding<NutritionServingRatio> {
        Binding(
            get: { self.itemRatios[itemName] ?? .full },
            set: { self.itemRatios[itemName] = $0 }
        )
    }

    func applyRecognition(_ updated: NutritionRecognitionResult) {
        recognition = updated
        itemRatios = Dictionary(
            uniqueKeysWithValues: updated.draft.items.map { item in
                (item.name, NutritionServingRatio.closest(to: item.servingRatio))
            }
        )
    }

    func clearError() {
        errorMessageKey = nil
    }

    func save(onSuccess: @escaping () -> Void) async {
        guard isSaving == false else { return }
        isSaving = true
        errorMessageKey = nil
        defer { isSaving = false }

        let request = NutritionDraftBuilder.makeCreateRequest(
            memberID: memberID,
            date: date,
            mealType: mealType,
            recognition: recognition,
            servingRatios: itemRatios
        )

        do {
            let record = try await dependencies.mealRecordUseCase.createMealRecord(request)
            if let member = dependencies.memberContextStore.context.members.first(where: { $0.id == memberID }) {
                await dependencies.healthKitSyncUseCase.writeMealRecordIfNeeded(member: member, record: record)
            }
            NotificationCenter.default.post(name: .nutritionMealRecordDidSave, object: nil)
            onSuccess()
        } catch {
            errorMessageKey = NutritionErrorMapper.messageKey(for: error)
        }
    }

    private func estimateItemOverview(
        item: SparkNutritionAPI.RemoteNutritionRecognitionItem,
        ratio: Double
    ) -> NutritionOverviewGridData {
        let draftOverview = recognition.draft.overview
        let itemCount = max(1, recognition.draft.items.count)
        return NutritionDraftBuilder.scaledOverview(
            NutritionOverviewGridData(
                energyKcal: draftOverview.energyKcal / Double(itemCount),
                proteinGrams: draftOverview.proteinG / Double(itemCount),
                carbohydrateGrams: draftOverview.carbohydrateG / Double(itemCount),
                fatGrams: draftOverview.fatG / Double(itemCount)
            ),
            ratio: ratio
        )
    }
}

struct NutritionRecognitionSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NutritionRecognitionSummaryViewModel
    @State private var showEditDetail = false

    private let dependencies: NutritionFeatureDependencies
    private let memberID: Int
    private let date: Date
    private let mealType: NutritionMealType
    let image: UIImage?
    let onUpdated: (NutritionRecognitionResult) -> Void
    let onSaveSuccess: () -> Void

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        mealType: NutritionMealType,
        image: UIImage?,
        recognition: NutritionRecognitionResult,
        onUpdated: @escaping (NutritionRecognitionResult) -> Void,
        onSaveSuccess: @escaping () -> Void
    ) {
        self.dependencies = dependencies
        self.memberID = memberID
        self.date = date
        self.mealType = mealType
        self.image = image
        self.onUpdated = onUpdated
        self.onSaveSuccess = onSaveSuccess
        _viewModel = StateObject(
            wrappedValue: NutritionRecognitionSummaryViewModel(
                dependencies: dependencies,
                memberID: memberID,
                date: date,
                mealType: mealType,
                recognition: recognition
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Text(viewModel.recognition.draft.title)
                    .font(.title3.weight(.semibold))

                NutritionOverviewGridCard(data: viewModel.overview)

                if viewModel.recognition.draft.uncertainNotes.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("nutrition.recognition.summary.uncertain"))
                            .font(.headline)
                        ForEach(viewModel.recognition.draft.uncertainNotes, id: \.self) { note in
                            Text("• \(note)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("nutrition.recognition.summary.items"))
                        .font(.headline)
                    NutritionCardContainer(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.recognition.draft.items.enumerated()), id: \.offset) { index, item in
                                itemRow(item)
                                if index < viewModel.recognition.draft.items.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                    }
                }

                Button(L10n.text("nutrition.recognition.summary.edit_detail")) {
                    showEditDetail = true
                }
                .font(.subheadline)

                Button {
                    Task {
                        await viewModel.save {
                            dismiss()
                            onSaveSuccess()
                        }
                    }
                } label: {
                    Group {
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(L10n.text("nutrition.recognition.summary.confirm"))
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
                }
                .disabled(viewModel.isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("nutrition.recognition.summary.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditDetail) {
            NutritionRecognitionEditDetailView(
                dependencies: dependencies,
                memberID: memberID,
                mealType: mealType,
                initialText: viewModel.recognition.foodDescription ?? viewModel.recognition.draft.title,
                onUpdated: { updated in
                    viewModel.applyRecognition(updated)
                    onUpdated(updated)
                }
            )
        }
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

    private func itemRow(_ item: SparkNutritionAPI.RemoteNutritionRecognitionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name)
                .font(.subheadline.weight(.semibold))
            if item.servingDescription.isEmpty == false {
                Text(item.servingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            NutritionServingRatioPicker(selection: viewModel.binding(for: item.name))
        }
        .padding(16)
    }
}
