import Combine
import SwiftUI

/// 首页饮食营养入口展示模式。
enum HomeNutritionEntryDisplayMode: String, CaseIterable, Identifiable, Sendable {
    /// 简约版：单卡片进入饮食营养首页。
    case compact
    /// 通用版：内嵌总结 + 营养看板，与设计文档 §三 一致。
    case full

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .compact:
            return "settings.general.home_nutrition_entry.compact"
        case .full:
            return "settings.general.home_nutrition_entry.full"
        }
    }
}

/// 首页「饮食营养」分组，展示模式由 ``HomeNutritionEntryPreferencesStore`` 控制。
struct HomeNutritionEntrySection: View {
    let dependencies: NutritionFeatureDependencies
    let memberID: Int?

    @ObservedObject private var preferencesStore: HomeNutritionEntryPreferencesStore
    @StateObject private var viewModel: HomeNutritionEntryViewModel

    init(
        dependencies: NutritionFeatureDependencies,
        memberID: Int?,
        preferencesStore: HomeNutritionEntryPreferencesStore = .shared
    ) {
        self.dependencies = dependencies
        self.memberID = memberID
        _preferencesStore = ObservedObject(wrappedValue: preferencesStore)
        _viewModel = StateObject(
            wrappedValue: HomeNutritionEntryViewModel(
                dashboardUseCase: dependencies.dashboardUseCase,
                healthKitSyncUseCase: dependencies.healthKitSyncUseCase,
                memberContextStore: dependencies.memberContextStore,
                logger: dependencies.logger
            )
        )
    }

    var body: some View {
        switch preferencesStore.displayMode {
        case .compact:
            compactSection
        case .full:
            fullSection
        }
    }

    // MARK: - 简约版

    private var compactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("home.nutrition.title"), systemImage: "fork.knife")
                    .font(.headline)
                Spacer()
            }

            NavigationLink {
                NutritionHomeView(dependencies: dependencies)
                    .hidesMainTabBarWhenPushed()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.pie.fill")
                        .font(.title3)
                        .foregroundStyle(Color(uiColor: .systemGreen))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(uiColor: .systemGreen).opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("home.nutrition.entry.title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(L10n.text("home.nutrition.entry.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(memberID == nil)
        }
    }

    // MARK: - 通用版

    private var fullSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            fullSectionHeader

            if memberID == nil {
                unavailableCard
            } else {
                fullContentSection
            }
        }
        .task(id: reloadTaskID) {
            guard preferencesStore.displayMode == .full else { return }
            await viewModel.reload(memberID: memberID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionMealRecordDidSave)) { _ in
            guard preferencesStore.displayMode == .full else { return }
            Task { await viewModel.reload(memberID: memberID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionEnergyBurnDidChange)) { _ in
            guard preferencesStore.displayMode == .full else { return }
            Task { await viewModel.reload(memberID: memberID) }
        }
    }

    private var reloadTaskID: String {
        "\(memberID ?? -1)-\(preferencesStore.displayMode.rawValue)"
    }

    private var fullSectionHeader: some View {
        HStack {
            Label(L10n.text("home.nutrition.title"), systemImage: "fork.knife")
                .font(.headline)
            Spacer()
            if memberID != nil {
                NavigationLink {
                    NutritionHomeView(dependencies: dependencies)
                        .hidesMainTabBarWhenPushed()
                } label: {
                    Text(L10n.text("home.nutrition.home_entry"))
                        .font(.subheadline)
                }
            }
        }
    }

    private var unavailableCard: some View {
        NutritionCardContainer {
            Text(L10n.text("nutrition.error.invalid_member"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var fullContentSection: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            NutritionLoadingStateView(messageKey: "nutrition.home.loading")
        case .error(let messageKey):
            NutritionErrorStateView(
                messageKey: messageKey,
                retryTitleKey: "nutrition.common.retry"
            ) {
                Task { await viewModel.reload(memberID: memberID) }
            }
        case .content(let dashboard):
            NutritionSummarySectionView(
                dashboard: dashboard,
                dashboardUseCase: dependencies.dashboardUseCase,
                dependencies: dependencies,
                memberID: memberID ?? 0,
                date: viewModel.selectedDate
            )

            NutritionMealsSectionView(
                meals: dashboard.meals,
                dependencies: dependencies,
                memberID: memberID ?? 0,
                date: viewModel.selectedDate
            )
        }
    }
}

@MainActor
private final class HomeNutritionEntryViewModel: ObservableObject {
    @Published private(set) var loadState: NutritionHomeLoadState = .idle
    @Published private(set) var selectedDate: Date = .now

    private let dashboardUseCase: NutritionDashboardUseCase
    private let healthKitSyncUseCase: NutritionHealthKitSyncUseCase
    private let memberContextStore: MemberContextStore
    private let logger: Logger

    init(
        dashboardUseCase: NutritionDashboardUseCase,
        healthKitSyncUseCase: NutritionHealthKitSyncUseCase,
        memberContextStore: MemberContextStore,
        logger: Logger
    ) {
        self.dashboardUseCase = dashboardUseCase
        self.healthKitSyncUseCase = healthKitSyncUseCase
        self.memberContextStore = memberContextStore
        self.logger = logger
    }

    func reload(memberID: Int?) async {
        guard let memberID else {
            loadState = .error(messageKey: "nutrition.error.invalid_member")
            return
        }

        loadState = .loading
        selectedDate = .now

        do {
            if let member = memberContextStore.context.members.first(where: { $0.id == memberID }) {
                await healthKitSyncUseCase.syncTodayIfNeeded(member: member, date: selectedDate)
            }

            let dashboard = try await dashboardUseCase.loadDashboard(
                memberID: memberID,
                date: selectedDate
            )
            loadState = .content(dashboard)
        } catch {
            let messageKey = NutritionErrorMapper.messageKey(for: error)
            logger.warning(
                "首页饮食营养看板加载失败 memberID=\(memberID) error=\(error.localizedDescription)",
                module: .nutrition
            )
            loadState = .error(messageKey: messageKey)
        }
    }
}
