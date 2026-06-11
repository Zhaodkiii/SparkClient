import SwiftUI

struct NutritionSummaryDetailView: View {
    @StateObject private var viewModel: NutritionSummaryDetailViewModel
    private let dependencies: NutritionFeatureDependencies
    private let memberID: Int
    private let date: Date

    @State private var isTrackingFood = false

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        initialDashboard: NutritionDashboardViewData? = nil
    ) {
        self.dependencies = dependencies
        self.memberID = memberID
        self.date = date
        _viewModel = StateObject(
            wrappedValue: NutritionSummaryDetailViewModel(
                dashboardUseCase: dependencies.dashboardUseCase,
                memberID: memberID,
                date: date,
                initialDashboard: initialDashboard
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.loadState {
                case .idle, .loading:
                    NutritionLoadingStateView(messageKey: "nutrition.home.loading")
                case .error(let messageKey):
                    NutritionErrorStateView(
                        messageKey: messageKey,
                        retryTitleKey: "nutrition.common.retry"
                    ) {
                        Task { await viewModel.reload() }
                    }
                case .content:
                    if let detail = viewModel.detail {
                        contentView(detail)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("nutrition.summary.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            trackFoodBar
        }
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionMealRecordDidSave)) { _ in
            Task { await viewModel.reload() }
        }
        .notificationFullScreenCover(
            isPresented: $isTrackingFood,
            store: dependencies.notificationStore
        ) {
            CompatibleNavigationContainer {
                NutritionFoodAddView(
                    dependencies: dependencies,
                    memberID: memberID,
                    date: date,
                    mealType: Self.suggestedMealType(now: Date())
                )
            }
        }
    }

    private var trackFoodBar: some View {
        Button {
            isTrackingFood = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.headline)
                Text(L10n.text("nutrition.summary.detail.track_food"))
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    /// Chooses a sensible default meal slot based on the time of day so the
    /// docked "track food" action can open the add-food flow without an extra
    /// meal picker step.
    private static func suggestedMealType(now: Date) -> NutritionMealType {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<10:
            return .breakfast
        case 10..<15:
            return .lunch
        case 15..<21:
            return .dinner
        default:
            return .snack
        }
    }

    @ViewBuilder
    private func contentView(_ detail: NutritionSummaryDetailViewData) -> some View {
        NutritionMacroProgressCard(
            titleKey: "nutrition.detail.macro_intake.title",
            data: detail.macroProgress
        )

        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("nutrition.summary.detail.meals.title"))
                .font(.headline)
            NutritionMealSegmentedPicker(selection: $viewModel.selectedMeal)

            if let macroProgress = viewModel.selectedMealMacroProgress {
                NutritionMacroProgressCard(
                    titleKey: "nutrition.detail.meal_macro.title",
                    data: macroProgress
                )
            }
        }

        if let chart = viewModel.selectedMealRatioChart ?? Optional(detail.macroRatioChart) {
            NutritionMacroRatioBarChartCard(
                titleKey: "nutrition.detail.macro_ratio.title",
                data: chart
            )
        }

        NutritionDetailInfoCard(
            titleKey: "nutrition.detail.info.title",
            data: detail.detailInfo
        )
    }
}

struct NutritionDetailView: View {
    @StateObject private var viewModel: NutritionDetailViewModel
    private let dependencies: NutritionFeatureDependencies

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date
    ) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: NutritionDetailViewModel(
                mealRecordUseCase: dependencies.mealRecordUseCase,
                memberID: memberID,
                date: date
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.loadState {
                case .idle, .loading:
                    NutritionLoadingStateView(messageKey: "nutrition.home.loading")
                case .error(let messageKey):
                    NutritionErrorStateView(
                        messageKey: messageKey,
                        retryTitleKey: "nutrition.common.retry"
                    ) {
                        Task { await viewModel.reload() }
                    }
                case .content:
                    if viewModel.groups.isEmpty {
                        NutritionEmptyStateView(
                            titleKey: "nutrition.detail.empty.title",
                            subtitleKey: "nutrition.detail.empty.subtitle"
                        )
                    } else {
                        ForEach(viewModel.groups) { group in
                            mealGroupSection(group)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("nutrition.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.hasEditableRecords {
                    MainNavigationLink {
                        NutritionMealFoodEditListView(
                            records: viewModel.records,
                            memberID: viewModel.memberID,
                            date: viewModel.date,
                            mealType: nil,
                            dependencies: dependencies
                        )
                    } label: {
                        Text(L10n.text("nutrition.common.edit"))
                    }
                }
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionMealRecordDidSave)) { _ in
            Task { await viewModel.reload() }
        }
    }

    private func mealGroupSection(_ group: NutritionMealGroupViewData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(group.mealType.localizationKey))
                .font(.headline)

            NutritionCardContainer {
                VStack(spacing: 0) {
                    ForEach(Array(group.foods.enumerated()), id: \.element.id) { index, food in
                        if let record = viewModel.record(for: food) {
                            MainNavigationLink {
                                NutritionMealFoodDetailEditView(
                                    row: food,
                                    record: record,
                                    mealType: group.mealType,
                                    dependencies: dependencies,
                                    memberID: viewModel.memberID
                                )
                            } label: {
                                NutritionMealFoodRowView(row: food)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NutritionMealFoodRowView(row: food)
                        }

                        if index < group.foods.count - 1 {
                            Divider()
                        }
                    }
                    Divider()
                    HStack {
                        Text(L10n.text("nutrition.detail.meal_total"))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(NutritionFormatting.energyKcal(group.totalEnergyKcal))
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

struct NutritionMealDetailView: View {
    @StateObject private var viewModel: NutritionMealDetailViewModel
    private let mealType: NutritionMealType
    private let dependencies: NutritionFeatureDependencies
    private let memberID: Int
    private let date: Date

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int,
        date: Date,
        mealType: NutritionMealType
    ) {
        self.dependencies = dependencies
        self.memberID = memberID
        self.date = date
        self.mealType = mealType
        _viewModel = StateObject(
            wrappedValue: NutritionMealDetailViewModel(
                dependencies: dependencies,
                memberID: memberID,
                date: date,
                mealType: mealType
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.loadState {
                case .idle, .loading:
                    NutritionLoadingStateView(messageKey: "nutrition.home.loading")
                case .error(let messageKey):
                    NutritionErrorStateView(
                        messageKey: messageKey,
                        retryTitleKey: "nutrition.common.retry"
                    ) {
                        Task { await viewModel.reload() }
                    }
                case .content:
                    if let detail = viewModel.detail {
                        contentView(detail)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text(mealType.localizationKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if let detail = viewModel.detail, detail.foods.isEmpty == false {
                        MainNavigationLink {
                            NutritionMealFoodEditListView(
                                records: detail.records,
                                memberID: memberID,
                                date: date,
                                mealType: mealType,
                                dependencies: dependencies
                            )
                        } label: {
                            Text(L10n.text("nutrition.common.edit"))
                        }
                    }
                    MainNavigationLink {
                        NutritionFoodAddView(
                            dependencies: dependencies,
                            memberID: memberID,
                            date: date,
                            mealType: mealType
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionMealRecordDidSave)) { _ in
            Task { await viewModel.reload() }
        }
        .alert(
            L10n.text("nutrition.confirm.save_failed.title"),
            isPresented: mealErrorAlertBinding
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            if let key = viewModel.errorMessageKey {
                Text(L10n.text(key))
            }
        }
    }

    private var mealErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessageKey != nil },
            set: { if $0 == false { viewModel.clearError() } }
        )
    }

    @ViewBuilder
    private func contentView(_ detail: NutritionMealDetailViewData) -> some View {
        mealImageSection(detail)

        NutritionOverviewGridCard(data: detail.overview)

        if detail.foods.isEmpty {
            NutritionEmptyStateView(
                titleKey: "nutrition.meal.empty.title",
                subtitleKey: "nutrition.meal.empty.subtitle"
            )
        } else {
            NutritionCardContainer {
                VStack(spacing: 0) {
                    ForEach(Array(detail.foods.enumerated()), id: \.element.id) { index, food in
                        if let record = detail.records.first(where: { $0.id == food.recordID }) {
                            MainNavigationLink {
                                NutritionMealFoodDetailEditView(
                                    row: food,
                                    record: record,
                                    mealType: mealType,
                                    dependencies: dependencies,
                                    memberID: memberID
                                )
                            } label: {
                                NutritionMealFoodRowView(row: food)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NutritionMealFoodRowView(row: food)
                        }

                        if index < detail.foods.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }

        NutritionMacroProgressCard(
            titleKey: "nutrition.detail.macro_intake.title",
            data: detail.macroProgress
        )

        NutritionDetailInfoCard(
            titleKey: "nutrition.detail.info.title",
            data: detail.detailInfo
        )
    }

    private func mealImageSection(_ detail: NutritionMealDetailViewData) -> some View {
        NutritionCardContainer {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 180)
                if let url = detail.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            placeholderImage
                        }
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    placeholderImage
                }
            }
        }
    }

    private var placeholderImage: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(L10n.text("nutrition.meal.no_image"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
