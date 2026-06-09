import Combine
import SwiftUI

struct NutritionHistoryView: View {
    @StateObject private var viewModel: NutritionHistoryViewModel

    init(mealRecordUseCase: NutritionMealRecordUseCase, memberID: Int) {
        _viewModel = StateObject(
            wrappedValue: NutritionHistoryViewModel(
                mealRecordUseCase: mealRecordUseCase,
                memberID: memberID
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.loadState {
                case .idle, .loading:
                    NutritionLoadingStateView(messageKey: "nutrition.history.loading")
                case .error(let messageKey):
                    NutritionErrorStateView(
                        messageKey: messageKey,
                        retryTitleKey: "nutrition.common.retry"
                    ) {
                        Task { await viewModel.reload() }
                    }
                case .content:
                    if viewModel.days.isEmpty {
                        NutritionEmptyStateView(
                            titleKey: "nutrition.history.empty.title",
                            subtitleKey: "nutrition.history.empty.subtitle"
                        )
                    } else {
                        ForEach(viewModel.days) { day in
                            daySection(day)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("nutrition.history.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.reload() }
    }

    private func daySection(_ day: NutritionHistoryDayViewData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Spacer()
                Text(NutritionFormatting.energyKcal(day.totalEnergyKcal))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NutritionCardContainer(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(day.records.enumerated()), id: \.element.id) { index, record in
                        historyRow(record)
                        if index < day.records.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ record: NutritionHistoryRecordViewData) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(record.mealType.localizationKey))
                    .font(.subheadline.weight(.semibold))
                if record.title.isEmpty == false {
                    Text(record.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(
                    String(
                        format: L10n.text("nutrition.history.record.meta"),
                        locale: Locale.current,
                        record.foodCount,
                        record.consumedAt.formatted(date: .omitted, time: .shortened)
                    )
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(NutritionFormatting.energyKcal(record.energyKcal))
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
    }
}

@MainActor
final class NutritionHistoryViewModel: ObservableObject {
    @Published private(set) var days: [NutritionHistoryDayViewData] = []
    @Published private(set) var loadState: NutritionHomeLoadState = .idle

    private let mealRecordUseCase: NutritionMealRecordUseCase
    private let memberID: Int
    private var hasLoaded = false

    init(mealRecordUseCase: NutritionMealRecordUseCase, memberID: Int) {
        self.mealRecordUseCase = mealRecordUseCase
        self.memberID = memberID
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        loadState = .loading
        let calendar = Calendar.current
        let dateTo = calendar.startOfDay(for: Date())
        guard let dateFrom = calendar.date(byAdding: .day, value: -29, to: dateTo) else {
            loadState = .error(messageKey: "nutrition.error.invalid_date")
            return
        }

        do {
            let loaded = try await mealRecordUseCase.loadHistory(
                memberID: memberID,
                dateFrom: dateFrom,
                dateTo: dateTo
            )
            days = loaded
            loadState = .content(
                NutritionDashboardViewData(
                    memberID: memberID,
                    date: dateTo,
                    consumedEnergyKcal: 0,
                    remainingEnergyKcal: 0,
                    burnedEnergyKcal: 0,
                    targetEnergyKcal: 0,
                    intakeProgress: 0,
                    overview: .init(energyKcal: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0),
                    carbohydrate: .init(current: 0, target: 0, unit: "g"),
                    protein: .init(current: 0, target: 0, unit: "g"),
                    fat: .init(current: 0, target: 0, unit: "g"),
                    macroRatioChart: .init(
                        carbohydrate: .init(currentPercent: 0, targetPercent: 100),
                        protein: .init(currentPercent: 0, targetPercent: 100),
                        fat: .init(currentPercent: 0, targetPercent: 100)
                    ),
                    meals: []
                )
            )
        } catch {
            loadState = .error(messageKey: NutritionErrorMapper.messageKey(for: error))
        }
    }
}
