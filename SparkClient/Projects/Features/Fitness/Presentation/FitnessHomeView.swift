import SwiftUI
import UIKit

/// 运动健康 Tab 根视图：健康仪表盘。
///
/// 数据来源：
/// - 身材管理（体重/BMI）来自用户健康档案（营养目标）；
/// - 睡眠/步数/运动/热量/站立/锻炼时长/血氧/心率来自苹果健康（HealthKit）；
/// - 饮食记录来自营养模块当日数据；
/// - 血糖/血压为后续设备接入预留占位。
struct FitnessHomeView: View {
    @StateObject private var viewModel: FitnessHomeViewModel
    @ObservedObject private var memberContextStore: MemberContextStore

    private let dependencies: FitnessFeatureDependencies
    /// 嵌入 IOS26HomeView 分页时由宿主统一提供标题与工具栏，置 false 隐藏本视图的导航栏外观。
    private let showsNavigationChrome: Bool

    init(dependencies: FitnessFeatureDependencies, showsNavigationChrome: Bool = true) {
        self.dependencies = dependencies
        self.showsNavigationChrome = showsNavigationChrome
        _viewModel = StateObject(wrappedValue: FitnessHomeViewModel(dashboardUseCase: dependencies.dashboardUseCase))
        _memberContextStore = ObservedObject(wrappedValue: dependencies.memberContextStore)
    }

    var body: some View {
        Group {
            if showsNavigationChrome {
                pageContent
                    .navigationTitle(L10n.text("fitness.home.title"))
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar { toolbarContent }
            } else {
                pageContent
            }
        }
    }

    private var pageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let dashboard = currentDashboard,
                   !dashboard.isAppleHealthBound,
                   !viewModel.authorizationPromptDismissed {
                    authorizationPrompt
                }
                stateSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable {
            await viewModel.reload(memberID: resolvedMemberID)
        }
        .task {
            await viewModel.loadIfNeeded(memberID: resolvedMemberID)
        }
        .onChange(of: memberContextStore.context.selectedMemberID) { _, newValue in
            Task {
                await viewModel.reload(memberID: newValue ?? memberContextStore.context.selectedMember?.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutritionMealRecordDidSave)) { _ in
            Task { await viewModel.reload(memberID: resolvedMemberID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.reload(memberID: resolvedMemberID) }
        }
    }

    // MARK: - 状态区

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            FitnessLoadingStateView()
        case .error(let message):
            FitnessErrorStateView(message: message) {
                Task { await viewModel.reload(memberID: resolvedMemberID) }
            }
        case .content(let dashboard):
            dashboardSection(dashboard)
        }
    }

    @ViewBuilder
    private func dashboardSection(_ dashboard: FitnessDashboard) -> some View {
        bodyMetricsCard(dashboard.bodyMetrics)

        ForEach(Self.gridPairs, id: \.self) { pair in
            HStack(spacing: 14) {
                if let metric = dashboard.metric(pair[0]) {
                    metricCard(metric)
                        .frame(maxWidth: .infinity)
                }
                if let metric = dashboard.metric(pair[1]) {
                    metricCard(metric)
                        .frame(maxWidth: .infinity)
                }
            }
        }

        if let heartRate = dashboard.metric(.heartRate) {
            metricCard(heartRate)
        }

        if !dashboard.isAppleHealthBound {
            privacyHint
        }
    }

    // MARK: - 身材管理卡片

    private func bodyMetricsCard(_ body: FitnessBodyMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("fitness.card.weight"), systemImage: "person.text.rectangle")
                    .font(.headline)
                Spacer()
            }

            HStack(alignment: .lastTextBaseline, spacing: 24) {
                metricValue(
                    value: body.weightKg.map { String(format: "%.2f", $0) },
                    unit: "KG"
                )
                metricValue(
                    value: body.bmi.map { String(format: "%.1f", $0) },
                    unit: "BMI"
                )
                metricValue(
                    value: body.bodyFatPercent.map { String(format: "%.1f", $0) },
                    unit: L10n.text("fitness.card.weight.body_fat", fallback: "体脂率")
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: Self.cardShape())
        .overlay(Self.cardShape().strokeBorder(.quaternary, lineWidth: 1))
    }

    // MARK: - 指标卡片

    private func metricCard(_ metric: FitnessMetricValue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Self.title(for: metric.type), systemImage: Self.icon(for: metric.type))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let badge = Self.statusBadge(metric.status) {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().strokeBorder(.orange, lineWidth: 1))
                }
            }

            Text(Self.timestampText(metric.timestamp))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.mainText(metric))
                    .font(.title2.weight(.bold))
                if metric.displayText == nil, !metric.unit.isEmpty, metric.value != nil {
                    Text(metric.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let label = metric.label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: Self.cardShape())
        .overlay(Self.cardShape().strokeBorder(.quaternary, lineWidth: 1))
    }

    // MARK: - 授权引导

    private var authorizationPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text("fitness.auth.title"), systemImage: "link")
                .font(.headline)
            Text(L10n.text("fitness.auth.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                MainNavigationLink {
                    AddDeviceView(viewModel: DeviceBindingUseCase(memberContextStore: memberContextStore))
                } label: {
                    Text(L10n.text("fitness.auth.action"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(L10n.text("fitness.auth.later")) {
                    viewModel.hideAuthorizationPrompt()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: Self.cardShape())
        .overlay(Self.cardShape().strokeBorder(.quaternary, lineWidth: 1))
    }

    private var privacyHint: some View {
        Text(L10n.text("fitness.privacy.hint"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            memberSelector
        }
    }

    @ViewBuilder
    private var memberSelector: some View {
        if let member = memberContextStore.context.selectedMember {
            MemberProfileBindingMenu(
                memberContextStore: memberContextStore,
                selectedMemberID: memberContextStore.context.selectedMemberID,
                onSelect: { memberID in
                    guard let memberID, memberID != memberContextStore.context.selectedMemberID else { return }
                    memberContextStore.select(memberID: memberID)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            ) {
                MemberSelectorChip(
                    member: member,
                    badgeText: MemberSelectorChip.badgeText(for: member),
                    isSelected: false,
                    variant: .compactToolbar,
                    onSelect: {},
                    onViewDetail: {},
                    onShare: {}
                )
            }
        }
    }

    // MARK: - 辅助

    private var currentDashboard: FitnessDashboard? {
        if case .content(let dashboard) = viewModel.loadState {
            return dashboard
        }
        return nil
    }

    private var resolvedMemberID: Int? {
        memberContextStore.context.selectedMemberID ?? memberContextStore.context.selectedMember?.id
    }

    private static let gridPairs: [[FitnessMetricType]] = [
        [.sleep, .nutrition],
        [.steps, .workout],
        [.calories, .standHour],
        [.exerciseTime, .bloodOxygen],
        [.bloodGlucose, .bloodPressure],
    ]

    private static func cardShape() -> RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    private static func title(for type: FitnessMetricType) -> String {
        switch type {
        case .sleep: return L10n.text("fitness.card.sleep")
        case .nutrition: return L10n.text("fitness.card.nutrition")
        case .steps: return L10n.text("fitness.card.steps")
        case .workout: return L10n.text("fitness.card.workout")
        case .calories: return L10n.text("fitness.card.calories")
        case .standHour: return L10n.text("fitness.card.stand_hour")
        case .exerciseTime: return L10n.text("fitness.card.exercise_time")
        case .bloodOxygen: return L10n.text("fitness.card.blood_oxygen")
        case .heartRate: return L10n.text("fitness.card.heart_rate")
        case .bloodGlucose: return L10n.text("fitness.card.blood_glucose")
        case .bloodPressure: return L10n.text("fitness.card.blood_pressure")
        }
    }

    private static func icon(for type: FitnessMetricType) -> String {
        switch type {
        case .sleep: return "moon.zzz.fill"
        case .nutrition: return "fork.knife"
        case .steps: return "figure.walk"
        case .workout: return "list.bullet.clipboard.fill"
        case .calories: return "flame.fill"
        case .standHour: return "clock.fill"
        case .exerciseTime: return "stopwatch.fill"
        case .bloodOxygen: return "drop.fill"
        case .heartRate: return "heart.fill"
        case .bloodGlucose: return "drop.halffull"
        case .bloodPressure: return "cross.case.fill"
        }
    }

    private static func statusBadge(_ status: FitnessMetricStatus) -> String? {
        switch status {
        case .low: return L10n.text("fitness.status.low")
        case .high: return L10n.text("fitness.status.high")
        case .normal, .noData: return nil
        }
    }

    private static func timestampText(_ date: Date?) -> String {
        guard let date else { return L10n.text("fitness.data.no_data") }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private static func mainText(_ metric: FitnessMetricValue) -> String {
        if let displayText = metric.displayText {
            return displayText
        }
        guard let value = metric.value else {
            return L10n.text("fitness.data.no_data_value", fallback: "--")
        }
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    @ViewBuilder
    private func metricValue(value: String?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value ?? L10n.text("fitness.data.no_data_value", fallback: "--"))
                .font(.title2.weight(.bold))
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 加载 / 错误态

private struct FitnessLoadingStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.text("fitness.loading", fallback: "加载中"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct FitnessErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.text("fitness.retry", fallback: "重试"), action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

// MARK: - Preview

#Preview("Fitness Home") {
    CompatibleNavigationContainer {
        FitnessHomeView(dependencies: .preview)
    }
}

extension FitnessFeatureDependencies {
    @MainActor
    static var preview: FitnessFeatureDependencies {
        HomeFeatureDependencies.preview.fitnessDependencies
    }
}
