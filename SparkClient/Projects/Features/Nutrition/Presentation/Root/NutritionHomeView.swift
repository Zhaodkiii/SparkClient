import SwiftUI

struct NutritionHomeView: View {
    @StateObject private var viewModel: NutritionHomeViewModel
    @ObservedObject private var memberContextStore: MemberContextStore

    private let dependencies: NutritionFeatureDependencies
    /// 嵌入 IOS26HomeView 分页时由宿主统一提供标题与工具栏，置 false 隐藏本视图的导航栏外观。
    private let showsNavigationChrome: Bool

    init(dependencies: NutritionFeatureDependencies, showsNavigationChrome: Bool = true) {
        self.dependencies = dependencies
        self.showsNavigationChrome = showsNavigationChrome
        _viewModel = StateObject(wrappedValue: NutritionHomeViewModel(dependencies: dependencies))
        _memberContextStore = ObservedObject(wrappedValue: dependencies.memberContextStore)
    }

    var body: some View {
        Group {
            if showsNavigationChrome {
                pageContent
                    .navigationTitle(L10n.text("nutrition.home.title"))
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar { navigationToolbar }
            } else {
                pageContent
            }
        }
    }

    private var pageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dateSwitcher
                stateSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: memberContextStore.context.selectedMemberID) { newValue in
            viewModel.syncMemberSelection(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionMealRecordDidSave)) { _ in
            Task { await viewModel.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionEnergyBurnDidChange)) { _ in
            Task { await viewModel.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionGoalDidSave)) { _ in
            Task { await viewModel.reload() }
        }
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            MainNavigationLink {
                NutritionGoalView(
                    goalUseCase: dependencies.goalUseCase,
                    memberID: resolvedMemberID,
                    member: memberContextStore.context.selectedMember,
                    onSaved: {
                        Task { await viewModel.reload() }
                    }
                )
            } label: {
                Image(systemName: "target")
            }
            .disabled(resolvedMemberID == 0)
            .accessibilityLabel(L10n.text("nutrition.goal.title", fallback: "我的目标"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            MainNavigationLink {
                NutritionHistoryView(
                    mealRecordUseCase: dependencies.mealRecordUseCase,
                    memberID: resolvedMemberID
                )
            } label: {
                Text(L10n.text("nutrition.history.entry"))
            }
        }
    }

    private var dateSwitcher: some View {
        HStack {
            Button {
                shiftDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            VStack(spacing: 2) {
                Text(dateTitle)
                    .font(.subheadline.weight(.semibold))
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                shiftDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state.loadState {
        case .idle, .loading:
            NutritionLoadingStateView(messageKey: "nutrition.home.loading")
        case .error(let messageKey):
            NutritionErrorStateView(
                messageKey: messageKey,
                retryTitleKey: "nutrition.common.retry"
            ) {
                Task { await viewModel.reload() }
            }
        case .content(let dashboard):
            NutritionSummarySectionView(
                dashboard: dashboard,
                dependencies: dependencies,
                memberID: resolvedMemberID,
                date: viewModel.state.selectedDate
            )

            NutritionMealsSectionView(
                meals: dashboard.meals,
                dependencies: dependencies,
                memberID: resolvedMemberID,
                date: viewModel.state.selectedDate
            )
        }
    }

    private var resolvedMemberID: Int {
        viewModel.state.selectedMemberID ?? memberContextStore.context.selectedMemberID ?? 0
    }

    private var dateTitle: String {
        Calendar.current.isDateInToday(viewModel.state.selectedDate)
            ? L10n.text("nutrition.date.today")
            : L10n.text("nutrition.date.selected")
    }

    private var formattedDate: String {
        viewModel.state.selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func shiftDate(by days: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: viewModel.state.selectedDate) else {
            return
        }
        viewModel.setSelectedDate(newDate)
    }
}

#Preview("Nutrition Home") {
    CompatibleNavigationContainer {
        NutritionHomeView(dependencies: .preview)
    }
}

extension NutritionFeatureDependencies {
    @MainActor
    static var preview: NutritionFeatureDependencies {
        let logger = ConsoleLogger()
        let api = NutritionAPI(configuration: AppContainer.preview.backend.configuration)
        let repository = NutritionRepository(api: api)
        let promptFactory = NutritionPromptFactory()
        let imageDescriber = NutritionFoodImageDescriber(
            runtimeService: AppContainer.preview.aiRuntimeService,
            configCenter: AppContainer.preview.aiConfigCenter,
            promptFactory: promptFactory,
            logger: logger
        )
        let intakeExtractor = NutritionIntakeStructuredExtractor(
            runtimeService: AppContainer.preview.aiRuntimeService,
            configCenter: AppContainer.preview.aiConfigCenter,
            promptFactory: promptFactory,
            jsonNormalizer: MedicalDocumentModelJSONNormalizer(),
            logger: logger
        )
        return NutritionFeatureDependencies(
            dashboardUseCase: NutritionDashboardUseCase(repository: repository, logger: logger),
            mealRecordUseCase: NutritionMealRecordUseCase(repository: repository, logger: logger),
            searchUseCase: NutritionSearchUseCase(repository: repository, logger: logger),
            healthKitSyncUseCase: NutritionHealthKitSyncUseCase(
                repository: repository,
                healthKitStore: NutritionHealthKitStore(logger: logger),
                logger: logger
            ),
            energyBurnUseCase: NutritionEnergyBurnUseCase(repository: repository, logger: logger),
            goalUseCase: NutritionGoalUseCase(repository: repository, logger: logger),
            recognitionPipeline: DefaultNutritionRecognitionPipeline(
                imageDescriber: imageDescriber,
                intakeExtractor: intakeExtractor,
                logger: logger
            ),
            configCenter: AppContainer.preview.aiConfigCenter,
            memberContextStore: AppContainer.preview.memberContextStore,
            notificationStore: AppContainer.preview.notificationStore,
            logger: logger
        )
    }
}
