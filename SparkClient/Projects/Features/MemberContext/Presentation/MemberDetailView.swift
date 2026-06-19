import Combine
import SwiftUI

/// 家庭成员详情页视图模型
/// 职责：加载成员详情、模块配置、饮食目标与饮食看板，并承接删除/解绑操作。
@MainActor
final class MemberDetailViewModel: ObservableObject {
    @Published private(set) var detail: SparkMedicalMemberAPI.MemberDetailResponse?
    @Published private(set) var moduleSettings: [SparkMedicalSyncAPI.RemoteMemberModuleSetting] = []
    @Published private(set) var nutritionGoalState: SparkNutritionAPI.RemoteNutritionGoalState?
    @Published private(set) var nutritionDashboard: SparkNutritionAPI.RemoteNutritionDashboard?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var supplementalErrorMessage: String?

    let bindingUseCase: ManageMemberBindingUseCase

    private let memberID: Int
    private let moduleSetupUseCase: MemberModuleSetupUseCase
    private let nutritionGoalUseCase: NutritionGoalUseCase
    private let nutritionDashboardUseCase: NutritionDashboardUseCase

    init(
        bindingUseCase: ManageMemberBindingUseCase,
        moduleSetupUseCase: MemberModuleSetupUseCase,
        nutritionGoalUseCase: NutritionGoalUseCase,
        nutritionDashboardUseCase: NutritionDashboardUseCase,
        memberID: Int
    ) {
        self.bindingUseCase = bindingUseCase
        self.moduleSetupUseCase = moduleSetupUseCase
        self.nutritionGoalUseCase = nutritionGoalUseCase
        self.nutritionDashboardUseCase = nutritionDashboardUseCase
        self.memberID = memberID
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        supplementalErrorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await bindingUseCase.fetchDetail(memberID: memberID)
        } catch {
            errorMessage = L10n.text("common.error")
            return
        }

        await loadSupplementalData()
    }

    func unbind() async throws {
        guard let bindingId = detail?.bindingId else { return }
        try await bindingUseCase.unbind(bindingID: bindingId)
    }

    func deleteOrUnbind() async throws -> DeleteOrUnbindResult? {
        guard let detail else { return nil }
        return try await bindingUseCase.deleteOrUnbind(
            memberID: memberID,
            bindingID: detail.bindingId,
            canDelete: detail.canDelete
        )
    }

    private func loadSupplementalData() async {
        async let modulesResult = capture { [self] in
            try await self.moduleSetupUseCase.loadModuleSettings(memberID: self.memberID)
        }
        async let goalResult = capture { [self] in
            try await self.nutritionGoalUseCase.loadGoalState(memberID: self.memberID)
        }
        async let dashboardResult = capture { [self] in
            try await self.nutritionDashboardUseCase.repository.fetchDashboard(memberID: self.memberID, date: Date())
        }

        let (modules, goal, dashboard) = await (modulesResult, goalResult, dashboardResult)
        var failedSupplementCount = 0

        switch modules {
        case .success(let value):
            moduleSettings = value.sorted { $0.displayOrder < $1.displayOrder }
        case .failure:
            moduleSettings = []
            failedSupplementCount += 1
        }

        switch goal {
        case .success(let value):
            nutritionGoalState = value
        case .failure:
            nutritionGoalState = nil
            failedSupplementCount += 1
        }

        switch dashboard {
        case .success(let value):
            nutritionDashboard = value
        case .failure:
            nutritionDashboard = nil
            failedSupplementCount += 1
        }

        if failedSupplementCount > 0 {
            supplementalErrorMessage = L10n.text(
                "home.members.detail.partial_data_error",
                fallback: "部分模块数据暂时不可用"
            )
        }
    }

    private func capture<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
}

/// 家庭成员详情页面
struct MemberDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemberDetailViewModel
    @ObservedObject var memberContextStore: MemberContextStore

    private let memberID: Int
    private let moduleSetupUseCase: MemberModuleSetupUseCase
    private let nutritionGoalUseCase: NutritionGoalUseCase
    private let homeDependencies: HomeFeatureDependencies
    let memberAPI: SparkMedicalMemberAPI
    let shareUseCase: ShareMemberUseCase
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDeleted: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showSharedUsersManage = false
    @State private var activeSetupSheet: MemberDetailSetupSheet?

    init(
        memberID: Int,
        bindingUseCase: ManageMemberBindingUseCase,
        moduleSetupUseCase: MemberModuleSetupUseCase,
        nutritionGoalUseCase: NutritionGoalUseCase,
        nutritionDashboardUseCase: NutritionDashboardUseCase,
        homeDependencies: HomeFeatureDependencies,
        memberContextStore: MemberContextStore,
        memberAPI: SparkMedicalMemberAPI,
        shareUseCase: ShareMemberUseCase,
        onShare: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: MemberDetailViewModel(
                bindingUseCase: bindingUseCase,
                moduleSetupUseCase: moduleSetupUseCase,
                nutritionGoalUseCase: nutritionGoalUseCase,
                nutritionDashboardUseCase: nutritionDashboardUseCase,
                memberID: memberID
            )
        )
        self.memberID = memberID
        self.moduleSetupUseCase = moduleSetupUseCase
        self.nutritionGoalUseCase = nutritionGoalUseCase
        self.homeDependencies = homeDependencies
        self.memberContextStore = memberContextStore
        self.memberAPI = memberAPI
        self.shareUseCase = shareUseCase
        self.onShare = onShare
        self.onEdit = onEdit
        self.onDeleted = onDeleted
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                loadingView
            } else if let detail = viewModel.detail {
                detailContent(detail)
            } else {
                errorView
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.text("home.members.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                actionMenu
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(deleteTitle, role: .destructive) {
                Task { await performDelete() }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(
                detail?.canDelete == true
                    ? L10n.text("home.members.detail.delete_profile.message")
                    : L10n.text("home.members.detail.unbind.message")
            )
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: $showSharedUsersManage) {
            if let detail = viewModel.detail {
                CompatibleNavigationContainer {
                    MemberSharedUsersManageView(
                        memberID: memberID,
                        detail: detail,
                        bindingUseCase: viewModel.bindingUseCase,
                        onShareMore: onShare,
                        onUpdated: {
                            Task { await viewModel.load() }
                        }
                    )
                }
            }
        }
        .sheet(item: $activeSetupSheet) { sheet in
            setupSheet(sheet)
        }
    }

    private var detail: SparkMedicalMemberAPI.MemberDetailResponse? {
        viewModel.detail
    }

    private var deleteTitle: String {
        detail?.canDelete == true
            ? L10n.text("home.members.detail.delete_profile")
            : L10n.text("home.members.detail.unbind")
    }

    private var actionMenu: some View {
        Menu {
            if viewModel.detail?.canShare == true {
                Button(L10n.text("home.members.action.share"), systemImage: "square.and.arrow.up") {
                    onShare()
                }
            }
            if viewModel.detail?.canEdit == true {
                Button(L10n.text("home.members.edit"), systemImage: "square.and.pencil") {
                    onEdit()
                }
            }
            if viewModel.detail?.canDelete == true || viewModel.detail?.canUnbind == true {
                Button(deleteTitle, systemImage: "trash", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(L10n.text("home.members.detail.loading", fallback: "正在加载成员详情"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(viewModel.errorMessage ?? L10n.text("common.error"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(L10n.text("common.retry", fallback: "重新加载")) {
                Task { await viewModel.load() }
            }
            .font(.headline)
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailContent(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection(detail)

                if let supplementalErrorMessage = viewModel.supplementalErrorMessage {
                    Label(supplementalErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                moduleOverviewSection(detail)
                profileSection(detail)
                bindingSection(detail)
                medicalOverviewSection(detail)
                nutritionOverviewSection
                sharedUsersSection(detail)
                dangerSection(detail)
            }
            .padding(20)
        }
    }

    private func headerSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    .frame(width: 76, height: 76)
                if let first = detail.name.first {
                    Text(String(first))
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 6) {
                Text(detail.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("\(relationshipTitle(detail.relationship)) · \(sharedUsersText(detail.sharedUserCount))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                pill(systemImage: "person.2.fill", text: relationshipTitle(detail.relationship), style: .neutral)
                pill(systemImage: "key.fill", text: roleLabel(detail.bindingRole), style: .accent)
                if detail.sharedUserCount > 1 {
                    pill(systemImage: "link.circle.fill", text: L10n.text("home.members.detail.shared", fallback: "已共享"), style: .neutral)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func moduleOverviewSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        detailCard {
            sectionHeader(
                title: L10n.text("home.members.detail.modules", fallback: "模块总览"),
                systemImage: "square.grid.2x2.fill"
            )
            VStack(spacing: 12) {
                moduleRow(
                    systemImage: "stethoscope.circle.fill",
                    title: L10n.text("home.members.detail.module.medical", fallback: "医疗"),
                    status: moduleStatusText(for: "medical", fallbackEnabled: hasMedicalData(detail)),
                    summary: medicalModuleSummary(detail),
                    actionTitle: moduleActionTitle(for: "medical", fallbackEnabled: hasMedicalData(detail)),
                    tint: Color(uiColor: .systemBlue)
                ) {
                    activeSetupSheet = .medical
                }
                Divider()
                moduleRow(
                    systemImage: "fork.knife.circle.fill",
                    title: L10n.text("home.members.detail.module.nutrition", fallback: "饮食"),
                    status: moduleStatusText(for: "nutrition", fallbackEnabled: hasNutritionData),
                    summary: nutritionModuleSummary,
                    actionTitle: moduleActionTitle(for: "nutrition", fallbackEnabled: hasNutritionData),
                    tint: Color(uiColor: .systemGreen)
                ) {
                    activeSetupSheet = .nutrition
                }
            }
        }
    }

    private func moduleRow(
        systemImage: String,
        title: String,
        status: String,
        summary: String,
        actionTitle: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(status)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                HStack {
                    Spacer(minLength: 44)
                    Label(actionTitle, systemImage: "slider.horizontal.3")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(actionTitle)
    }

    @ViewBuilder
    private func setupSheet(_ sheet: MemberDetailSetupSheet) -> some View {
        if let detail = viewModel.detail {
            switch sheet {
            case .medical:
                MemberMedicalSetupSheetView(
                    member: detail.domainMember,
                    medicalQueryAPI: homeDependencies.medicalQueryAPI,
                    setupUseCase: moduleSetupUseCase,
                    homeDependencies: homeDependencies
                ) { _ in
                    moduleSetupCompleted()
                }
            case .nutrition:
                MemberNutritionSetupSheetView(
                    member: detail.domainMember,
                    goalUseCase: nutritionGoalUseCase,
                    setupUseCase: moduleSetupUseCase
                ) { _ in
                    moduleSetupCompleted()
                }
            }
        }
    }

    private func moduleSetupCompleted() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeSetupSheet = nil
        Task { await viewModel.load() }
        memberContextStore.membersDidChange.send()
    }

    private func profileSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        detailCard {
            sectionHeader(title: L10n.text("home.members.detail.profile"), systemImage: "person.text.rectangle.fill")
            infoRow(L10n.text("home.members.field.gender"), genderTitle(detail.gender))
            if let birthDate = detail.birthDate {
                infoRow(L10n.text("home.members.field.birth_date"), birthDateText(birthDate))
            } else {
                infoRow(L10n.text("home.members.field.birth_date"), emptyText)
            }
            infoRow(L10n.text("home.members.detail.blood_type"), detail.bloodType.nilIfBlank ?? emptyText)
            infoRow(L10n.text("home.members.detail.allergies"), detail.allergies.isEmpty ? emptyText : detail.allergies.joined(separator: "、"))
            infoRow(L10n.text("home.members.detail.chronic"), detail.chronicConditions.isEmpty ? emptyText : detail.chronicConditions.joined(separator: "、"))
            infoRow(L10n.text("home.members.detail.notes"), detail.notes.nilIfBlank ?? emptyText)
        }
    }

    private func bindingSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        detailCard {
            sectionHeader(title: L10n.text("home.members.detail.my_binding"), systemImage: "person.badge.key.fill")
            infoRow(L10n.text("home.members.detail.my_relationship"), relationshipTitle(detail.myBinding?.relationship ?? detail.relationship))
            infoRow(L10n.text("home.members.detail.my_role"), roleLabel(detail.myBinding?.role ?? detail.bindingRole))
            infoRow(
                L10n.text("home.members.detail.is_primary", fallback: "是否默认成员"),
                (detail.myBinding?.isPrimary ?? detail.isPrimary)
                    ? L10n.text("common.yes", fallback: "是")
                    : L10n.text("common.no", fallback: "否")
            )
        }
    }

    private func medicalOverviewSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        detailCard {
            sectionHeader(title: L10n.text("home.members.detail.medical_overview"), systemImage: "stethoscope.circle.fill")
            let overview = detail.medicalOverview
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricTile(title: L10n.text("home.medical.card.medical_cases.title"), value: overview?.medicalCaseCount ?? 0, systemImage: "doc.text.fill")
                metricTile(title: L10n.text("home.medical.card.examination_reports.title"), value: overview?.healthExamReportCount ?? 0, systemImage: "heart.text.square.fill")
                metricTile(title: L10n.text("home.medical.card.medical_reports.title"), value: overview?.examinationReportCount ?? 0, systemImage: "list.clipboard.fill")
                metricTile(title: L10n.text("home.medical.card.medication_plans.title", fallback: "服药计划"), value: overview?.medicationPlanCount ?? 0, systemImage: "calendar.badge.clock")
            }
            if let lastUpdatedAt = overview?.lastUpdatedAt {
                Label(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nutritionOverviewSection: some View {
        detailCard {
            sectionHeader(
                title: L10n.text("home.members.detail.nutrition_overview", fallback: "饮食设定与数据"),
                systemImage: "fork.knife.circle.fill"
            )

            if let goalState = viewModel.nutritionGoalState, let goal = goalState.goal {
                let target = nutritionTarget(from: goalState)
                infoRow(L10n.text("nutrition.goal.type", fallback: "目标模式"), nutritionGoalTypeTitle(goal.goalType))
                infoRow(L10n.text("nutrition.goal.activity_level", fallback: "活跃水平"), activityLevelTitle(goal.activityLevel))
                infoRow(L10n.text("nutrition.goal.energy_target", fallback: "每日摄入目标"), kcalText(goal.dailyEnergyTargetKcal ?? target.energyKcal))
                infoRow("BMR / TDEE", bmrTdeeText(goal))
                infoRow(L10n.text("nutrition.goal.macro_target", fallback: "碳水 / 蛋白 / 脂肪"), macroTargetText(target))
                infoRow(L10n.text("nutrition.goal.current_weight", fallback: "当前体重"), kgText(goal.currentWeightKg))
                infoRow(L10n.text("nutrition.goal.target_weight", fallback: "目标体重"), kgText(goal.targetWeightKg))
                infoRow(L10n.text("nutrition.dashboard.record_progress", fallback: "记录进度"), nutritionRecordProgressText)
            } else {
                Label(
                    L10n.text("home.members.detail.nutrition_empty", fallback: "暂无饮食目标数据，可先去完善饮食模块"),
                    systemImage: "leaf.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sharedUsersSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        detailCard {
            HStack {
                sectionHeader(title: L10n.text("home.members.detail.shared_users"), systemImage: "person.2.fill")
                Spacer()
                if detail.canManageBindings == true, detail.sharedUsers?.isEmpty == false {
                    Button(L10n.text("home.members.binding.manage")) {
                        showSharedUsersManage = true
                    }
                    .font(.footnote.weight(.semibold))
                }
            }

            if let users = detail.sharedUsers, !users.isEmpty {
                VStack(spacing: 10) {
                    ForEach(users) { user in
                        sharedUserRow(user)
                    }
                }
            } else {
                Text(L10n.text("home.members.detail.shared_users_empty", fallback: "暂未与其他用户共享"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if detail.canShare == true {
                Button(action: onShare) {
                    Label(L10n.text("home.members.action.share"), systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func sharedUserRow(_ user: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(user.displayName.first.map(String.init) ?? "U")
                        .font(.subheadline.weight(.semibold))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(relationshipTitle(user.relationship))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(roleLabel(user.role))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func dangerSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        if detail.canDelete == true || detail.canUnbind == true {
            detailCard {
                sectionHeader(
                    title: L10n.text("home.members.detail.danger_zone", fallback: "危险操作"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(deleteTitle, systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.headline.weight(.semibold))
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
        }
        .foregroundStyle(.primary)
    }

    private func metricTile(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private enum PillStyle {
        case neutral
        case accent
    }

    private func pill(systemImage: String, text: String, style: PillStyle) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(style == .accent ? Color.accentColor.opacity(0.16) : Color(uiColor: .tertiarySystemGroupedBackground))
            )
            .foregroundStyle(style == .accent ? Color.accentColor : Color.primary)
    }

    private var emptyText: String {
        L10n.text("common.none", fallback: "暂无")
    }

    private var hasNutritionData: Bool {
        viewModel.nutritionGoalState?.goal != nil || hasNutritionRecords
    }

    private var nutritionModuleSummary: String {
        if let goalState = viewModel.nutritionGoalState, goalState.goal != nil {
            let target = nutritionTarget(from: goalState)
            return "\(kcalText(target.energyKcal)) · \(nutritionRecordProgressText)"
        }
        if hasNutritionRecords {
            return nutritionRecordProgressText
        }
        return L10n.text("home.members.detail.module.nutrition.empty", fallback: "未设置饮食目标")
    }

    private var hasNutritionRecords: Bool {
        guard let dashboard = viewModel.nutritionDashboard else { return false }
        return dashboard.meals.contains { $0.recordCount > 0 }
            || dashboard.serverIntake.energyKcal > 0
            || dashboard.appleHealthExternalIntake.energyKcal > 0
    }

    private var nutritionRecordProgressText: String {
        guard let dashboard = viewModel.nutritionDashboard else {
            return L10n.text("home.members.detail.nutrition.no_record", fallback: "暂无记录")
        }
        let totalMeals = max(dashboard.meals.count, 4)
        let recordedMeals = dashboard.meals.filter { $0.recordCount > 0 }.count
        if recordedMeals == 0 {
            return L10n.text("home.members.detail.nutrition.no_record_today", fallback: "今日暂无记录")
        }
        return String(
            format: L10n.text("home.members.detail.nutrition.record_progress", fallback: "今日已记 %d/%d 餐"),
            recordedMeals,
            totalMeals
        )
    }

    private func nutritionTarget(from goalState: SparkNutritionAPI.RemoteNutritionGoalState) -> SparkNutritionAPI.RemoteNutritionMacroTarget {
        guard let goal = goalState.goal else { return goalState.defaults }
        return SparkNutritionAPI.RemoteNutritionMacroTarget(
            energyKcal: goal.dailyEnergyTargetKcal ?? goalState.defaults.energyKcal,
            proteinG: goal.proteinTargetG ?? goalState.defaults.proteinG,
            carbohydrateG: goal.carbohydrateTargetG ?? goalState.defaults.carbohydrateG,
            fatG: goal.fatTargetG ?? goalState.defaults.fatG
        )
    }

    private func moduleStatusText(for moduleCode: String, fallbackEnabled: Bool) -> String {
        guard let setting = viewModel.moduleSettings.first(where: { $0.moduleCode == moduleCode }) else {
            return fallbackEnabled
                ? L10n.text("home.members.detail.module.enabled", fallback: "已开通")
                : L10n.text("home.members.detail.module.disabled", fallback: "未开通")
        }
        guard setting.isEnabled else {
            return L10n.text("home.members.detail.module.disabled", fallback: "未开通")
        }
        return setting.isCompleted
            ? L10n.text("home.members.detail.module.enabled", fallback: "已开通")
            : L10n.text("home.members.detail.module.pending", fallback: "待完善")
    }

    private func moduleActionTitle(for moduleCode: String, fallbackEnabled: Bool) -> String {
        let enabled = viewModel.moduleSettings.first(where: { $0.moduleCode == moduleCode })?.isEnabled ?? fallbackEnabled
        return enabled
            ? L10n.text("home.members.detail.module.maintain", fallback: "去维护")
            : L10n.text("home.members.detail.module.open", fallback: "去开通")
    }

    private func medicalModuleSummary(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> String {
        let overview = detail.medicalOverview
        return String(
            format: L10n.text("home.members.detail.medical_summary", fallback: "病历 %d · 体检 %d · 用药 %d"),
            overview?.medicalCaseCount ?? 0,
            overview?.healthExamReportCount ?? 0,
            overview?.medicationPlanCount ?? 0
        )
    }

    private func hasMedicalData(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> Bool {
        guard let overview = detail.medicalOverview else { return false }
        return overview.medicalCaseCount > 0
            || overview.healthExamReportCount > 0
            || overview.examinationReportCount > 0
            || overview.medicationPlanCount > 0
    }

    private func sharedUsersText(_ count: Int) -> String {
        String(
            format: L10n.text("home.members.detail.shared_users_count", fallback: "已绑定 %d 位用户"),
            count
        )
    }

    private func relationshipTitle(_ value: String) -> String {
        MemberRelationshipCatalog.displayTitle(for: value)
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "owner":
            return L10n.text("home.members.binding.role.owner")
        case "admin":
            return L10n.text("home.members.binding.role.admin")
        default:
            return L10n.text("home.members.binding.role.viewer")
        }
    }

    private func genderTitle(_ value: String) -> String {
        switch value {
        case "male":
            return L10n.text("home.members.gender.male", fallback: "男")
        case "female":
            return L10n.text("home.members.gender.female", fallback: "女")
        default:
            return value.nilIfBlank ?? emptyText
        }
    }

    private func nutritionGoalTypeTitle(_ value: String?) -> String {
        switch value {
        case "maintain":
            return L10n.text("nutrition.goal.type.maintain", fallback: "保持体重")
        case "lose_weight", "weight_loss":
            return L10n.text("nutrition.goal.type.lose_weight", fallback: "减重")
        case "gain_weight":
            return L10n.text("nutrition.goal.type.gain_weight", fallback: "增重")
        case "gain_muscle", "build_muscle":
            return L10n.text("nutrition.goal.type.gain_muscle", fallback: "打造肌肉")
        case .some(let value):
            return value
        case .none:
            return emptyText
        }
    }

    private func activityLevelTitle(_ value: String?) -> String {
        switch value {
        case "low":
            return L10n.text("nutrition.activity.low", fallback: "较低")
        case "medium":
            return L10n.text("nutrition.activity.medium", fallback: "中等")
        case "high":
            return L10n.text("nutrition.activity.high", fallback: "较高")
        case "very_high":
            return L10n.text("nutrition.activity.very_high", fallback: "很高")
        case .some(let value):
            return value
        case .none:
            return emptyText
        }
    }

    private func birthDateText(_ date: Date) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year
        if let years, years >= 0 {
            return "\(formatted) · \(years)\(L10n.text("common.years_old", fallback: "岁"))"
        }
        return formatted
    }

    private func kcalText(_ value: Double?) -> String {
        guard let value else { return emptyText }
        return "\(Int(value.rounded())) kcal"
    }

    private func kgText(_ value: Double?) -> String {
        guard let value else { return emptyText }
        return String(format: "%.1f kg", value)
    }

    private func bmrTdeeText(_ goal: SparkNutritionAPI.RemoteNutritionGoal?) -> String {
        guard goal?.bmrKcal != nil || goal?.tdeeKcal != nil else { return emptyText }
        return "\(kcalText(goal?.bmrKcal)) / \(kcalText(goal?.tdeeKcal))"
    }

    private func macroTargetText(_ target: SparkNutritionAPI.RemoteNutritionMacroTarget) -> String {
        "\(Int(target.carbohydrateG.rounded()))g / \(Int(target.proteinG.rounded()))g / \(Int(target.fatG.rounded()))g"
    }

    private func performDelete() async {
        do {
            _ = try await viewModel.deleteOrUnbind()
        } catch {
            return
        }
        memberContextStore.membersDidChange.send()
        onDeleted()
        dismiss()
    }
}

private enum MemberDetailSetupSheet: String, Identifiable {
    case medical
    case nutrition

    var id: String { rawValue }
}
