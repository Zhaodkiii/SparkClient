import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MedicationReminderManagementPage: View {
    @StateObject private var viewModel: MedicationReminderManagementViewModel
    @State private var expandedGroupIDs: Set<String> = []

    init(homeDependencies: HomeFeatureDependencies) {
        let accountID: Int64
        if case .signedIn(let session) = homeDependencies.sessionStore.state {
            accountID = session.accountID
        } else {
            accountID = 0
        }
        _viewModel = StateObject(
            wrappedValue: MedicationReminderManagementViewModel(
                accountID: accountID,
                syncCoordinator: homeDependencies.medicationReminderSyncCoordinator,
                preferencesStore: MedicationReminderPreferencesStore.shared,
                medicalQueryAPI: homeDependencies.medicalQueryAPI,
                memberContextStore: homeDependencies.memberContextStore,
                notificationClient: homeDependencies.notificationClient,
                logger: homeDependencies.logger
            )
        )
    }

    var body: some View {
        content
            .navigationTitle(L10n.text("medication_reminder.management.title", fallback: "已有通知"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { managementToolbar }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .medicationReminderPermissionExplanation(
                isPresented: $viewModel.showPermissionExplanation,
                onContinue: {
                    Task { await viewModel.confirmPermissionExplanationAndReschedule() }
                },
                onSkip: {
                    viewModel.skipPermissionExplanation()
                }
            )
            .alert(
                L10n.text("medication_reminder.management.clear_all.title"),
                isPresented: $viewModel.showClearAllConfirmation
            ) {
                Button(L10n.text("common.cancel", fallback: "取消"), role: .cancel) {}
                Button(L10n.text("medication_reminder.management.clear_all.confirm"), role: .destructive) {
                    Task { await viewModel.clearAllNotifications() }
                }
            } message: {
                Text(L10n.text("medication_reminder.management.clear_all.message"))
            }
            .alert(
                L10n.text("medication_reminder.management.cancel.title"),
                isPresented: Binding(
                    get: { viewModel.pendingCancelGroup != nil },
                    set: { if $0 == false { viewModel.pendingCancelGroup = nil } }
                )
            ) {
                Button(L10n.text("common.cancel", fallback: "取消"), role: .cancel) {
                    viewModel.pendingCancelGroup = nil
                }
                Button(L10n.text("medication_reminder.management.cancel.confirm"), role: .destructive) {
                    if let group = viewModel.pendingCancelGroup {
                        Task {
                            await viewModel.cancelNotification(group)
                            viewModel.pendingCancelGroup = nil
                        }
                    }
                }
            } message: {
                Text(L10n.text("medication_reminder.management.cancel.message"))
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.groups.isEmpty {
            loadingView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.pendingCount > 0 || viewModel.deliveredCount > 0 {
                        statisticsHeader
                    }
                    if viewModel.isPermissionDenied {
                        permissionBanner
                    }
                    privacyHint
                    if viewModel.groups.isEmpty {
                        emptyStateView
                    } else {
                        notificationList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    @ToolbarContentBuilder
    private var managementToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    Task { await viewModel.rescheduleNotifications() }
                } label: {
                    Label(
                        L10n.text("medication_reminder.management.reschedule"),
                        systemImage: "arrow.clockwise"
                    )
                }
                if viewModel.pendingCount > 0 || viewModel.deliveredCount > 0 {
                    Button(role: .destructive) {
                        viewModel.showClearAllConfirmation = true
                    } label: {
                        Label(
                            L10n.text("medication_reminder.management.clear_all"),
                            systemImage: "trash"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var statisticsHeader: some View {
        HStack(spacing: 24) {
            statisticColumn(
                title: L10n.text("medication_reminder.management.stats.pending"),
                value: viewModel.pendingCount,
                color: Color(uiColor: .systemBlue)
            )
            Divider().frame(height: 40)
            statisticColumn(
                title: L10n.text("medication_reminder.management.stats.delivered"),
                value: viewModel.deliveredCount,
                color: Color(uiColor: .systemGreen)
            )
            Spacer()
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statisticColumn(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("medication_reminder.management.permission_banner"))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Button(L10n.text("medication_reminder.management.open_settings")) {
                    viewModel.openSystemSettings()
                }
                .font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var privacyHint: some View {
        Text(
            viewModel.showsDrugNameInNotification
            ? L10n.text("medication_reminder.management.privacy.shows_drug_name")
            : L10n.text("medication_reminder.management.privacy.hides_drug_name")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationList: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.groups) { group in
                notificationCard(group)
            }
        }
    }

    private func notificationCard(_ group: MedicationReminderDisplayGroup) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    toggleExpanded(group.id)
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusIcon(for: group.status))
                        .font(.title3)
                        .foregroundStyle(statusColor(for: group.status))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        if let scheduledAt = group.scheduledAt {
                            Text(scheduledAt, format: .dateTime.hour().minute())
                                .font(.headline)
                            Text(relativeScheduleText(for: scheduledAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L10n.text("medication_reminder.management.unknown_time", fallback: "未知时间"))
                                .font(.headline)
                        }

                        Text(memberSummary(for: group))
                            .font(.subheadline.weight(.semibold))

                        Text(statusLabel(for: group.status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor(for: group.status))

                        if group.items.isEmpty == false {
                            Text(drugSummary(for: group))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else if group.rawBody.isEmpty == false {
                            Text(group.rawBody)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: expandedGroupIDs.contains(group.id) ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedGroupIDs.contains(group.id) {
                Divider()
                if group.items.isEmpty {
                    Text(L10n.text("medication_reminder.management.invalid_payload"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(group.items) { item in
                            HStack {
                                Text(item.drugName ?? L10n.text("medication_reminder.management.unknown_drug", fallback: "未知药品"))
                                    .font(.subheadline)
                                Spacer()
                                Text(
                                    String(
                                        format: L10n.text(
                                            "medication_reminder.management.dose_sequence",
                                            fallback: "第 %d 次"
                                        ),
                                        locale: .current,
                                        item.doseSequence
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            if item.id != group.items.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }

                if canCancel(group) {
                    Divider()
                    Button(role: .destructive) {
                        viewModel.pendingCancelGroup = group
                    } label: {
                        Text(L10n.text("medication_reminder.management.cancel_action"))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(L10n.text("common.loading", fallback: "加载中…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L10n.text("medication_reminder.management.empty.title"))
                .font(.headline)
            Text(L10n.text("medication_reminder.management.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.rescheduleNotifications() }
            } label: {
                Text(L10n.text("medication_reminder.management.reschedule"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .systemBlue))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func toggleExpanded(_ id: String) {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
        } else {
            expandedGroupIDs.insert(id)
        }
    }

    private func memberSummary(for group: MedicationReminderDisplayGroup) -> String {
        let count = max(group.items.count, 1)
        return String(
            format: L10n.text(
                "medication_reminder.management.member_items",
                fallback: "%@ · %d 项用药"
            ),
            locale: .current,
            group.memberName,
            count
        )
    }

    private func drugSummary(for group: MedicationReminderDisplayGroup) -> String {
        let names = group.items.compactMap(\.drugName)
        guard names.isEmpty == false else {
            return String(
                format: L10n.text(
                    "medication_reminder.management.items_count_only",
                    fallback: "%d 项用药"
                ),
                locale: .current,
                group.items.count
            )
        }
        return names.joined(separator: L10n.text("medication_reminder.management.drug_separator", fallback: "、"))
    }

    private func canCancel(_ group: MedicationReminderDisplayGroup) -> Bool {
        switch group.status {
        case .pending, .expired, .invalid:
            return true
        case .delivered:
            return true
        }
    }

    private func statusIcon(for status: MedicationReminderDisplayStatus) -> String {
        switch status {
        case .pending:
            return "clock.fill"
        case .delivered:
            return "checkmark.circle.fill"
        case .expired:
            return "exclamationmark.triangle.fill"
        case .invalid:
            return "questionmark.circle"
        }
    }

    private func statusColor(for status: MedicationReminderDisplayStatus) -> Color {
        switch status {
        case .pending:
            return Color(uiColor: .systemBlue)
        case .delivered:
            return Color(uiColor: .systemGreen)
        case .expired:
            return Color(uiColor: .systemOrange)
        case .invalid:
            return Color.secondary
        }
    }

    private func statusLabel(for status: MedicationReminderDisplayStatus) -> String {
        switch status {
        case .pending:
            return L10n.text("medication_reminder.management.status.pending")
        case .delivered:
            return L10n.text("medication_reminder.management.status.delivered")
        case .expired:
            return L10n.text("medication_reminder.management.status.expired")
        case .invalid:
            return L10n.text("medication_reminder.management.status.invalid")
        }
    }

    private func relativeScheduleText(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L10n.text("medication_reminder.management.schedule.today", fallback: "今天")
        }
        if calendar.isDateInTomorrow(date) {
            return L10n.text("medication_reminder.management.schedule.tomorrow", fallback: "明天")
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day {
            if days > 0 {
                return String(
                    format: L10n.text(
                        "medication_reminder.management.schedule.days_later",
                        fallback: "%d 天后"
                    ),
                    locale: .current,
                    days
                )
            }
            if days < 0 {
                return L10n.text("medication_reminder.management.schedule.overdue", fallback: "已过期")
            }
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

#if DEBUG
#Preview("Medication Reminder Management") {
    CompatibleNavigationContainer {
        MedicationReminderManagementPage(homeDependencies: .preview)
    }
}
#endif
