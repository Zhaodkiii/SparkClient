import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IOS26HomeActionItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case checkupPlan
        case reportInterpretation
        case medication
        case familyMedicineCabinet
        case familyArchive
    }

    let id: Kind
    let title: String
    let subtitle: String
    let symbolName: String
    let prominence: Prominence
    let isEnabled: Bool
    let actionLabel: String?

    enum Prominence {
        case primary
        case secondary
        case compact
    }
}

@available(iOS 26.0, *)
struct IOS26HomeDashboardView: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var taskManager: TaskManager
    let session: UserSession
    let actionHandler: IOS26HomeDashboardActionHandler
    @ObservedObject var chatListViewModel: ChatListViewModel
    @ObservedObject var deepTutorChatViewModel: DeepTutorChatViewModel

    @State private var loadingAction: IOS26HomeActionItem.Kind?

    private var taskSummary: IOS26HomeTaskSummary {
        IOS26HomeTaskSummaryBuilder.makeHomeTaskSummary(
            tasks: taskManager.tasks,
            lastSyncTime: taskManager.lastSyncTime,
            isLoading: taskManager.isSyncing,
            errorMessage: taskManager.lastSyncError
        )
    }

    private var hasMembers: Bool {
        (viewModel.dashboard?.members.isEmpty == false)
    }

    private var greeting: String {
        let name = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return L10n.text("ios26.home.greeting.generic")
        }
        return String(format: L10n.text("ios26.home.greeting.named"), name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                memberStrip
                taskSummarySection
                primaryActions
                secondaryActions
                familyArchiveAction
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: deepTutorChatViewModel.isCreatingConversation) { _, isCreating in
            if isCreating == false {
                loadingAction = nil
            }
        }
        .onChange(of: chatListViewModel.isCreatingQuickStartThread) { _, isCreating in
            if isCreating == false {
                loadingAction = nil
            }
        }
        .task {
            await taskManager.loadInitial(memberID: viewModel.selectedMemberID)
            await taskManager.syncIncremental(memberID: viewModel.selectedMemberID)
        }
        .onChange(of: viewModel.selectedMemberID) { _, memberID in
            Task {
                await taskManager.loadInitial(memberID: memberID)
                await taskManager.syncIncremental(memberID: memberID)
            }
        }
    }

    private var taskSummarySection: some View {
        IOS26HomeTaskSummaryView(
            summary: taskSummary,
            onOpenTaskCenter: openTaskCenter,
            onOpenTaskItem: { _ in openTaskCenter() },
            onRetrySync: {
                Task {
                    await taskManager.syncIncremental(memberID: viewModel.selectedMemberID)
                }
            }
        )
    }

    private func openTaskCenter() {
        triggerHaptic(style: .light)
        viewModel.activeSheet = .taskCenter
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(L10n.text("ios26.home.title"))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memberStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("ios26.home.current_member"))
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.dashboard?.members ?? []) { member in
                        memberChip(for: member)
                    }

                    Button {
                        viewModel.activeSheet = .addMember(.create())
                        triggerHaptic(style: .medium)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("home.members.add.title"))
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func memberChip(for member: Member) -> some View {
        let isSelected = member.id == viewModel.selectedMemberID
        return Button {
            viewModel.selectMember(member.id)
            triggerHaptic(style: .light)
        } label: {
            Text(member.name)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color(uiColor: .quaternaryLabel), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var primaryActions: some View {
        VStack(spacing: 14) {
            actionCard(for: checkupPlanItem)
            actionCard(for: reportInterpretationItem)
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 14) {
            compactActionCard(for: medicationItem)
                .frame(maxWidth: .infinity)
            compactActionCard(for: familyMedicineCabinetItem)
                .frame(maxWidth: .infinity)
        }
    }

    private var familyArchiveAction: some View {
        actionCard(for: familyArchiveItem)
    }

    private var checkupPlanItem: IOS26HomeActionItem {
        IOS26HomeActionItem(
            id: .checkupPlan,
            title: L10n.text("ios26.home.action.checkup_plan.title"),
            subtitle: L10n.text("ios26.home.action.checkup_plan.subtitle"),
            symbolName: "heart.text.clipboard",
            prominence: .primary,
            isEnabled: hasMembers,
            actionLabel: L10n.text("ios26.home.action.start")
        )
    }

    private var reportInterpretationItem: IOS26HomeActionItem {
        IOS26HomeActionItem(
            id: .reportInterpretation,
            title: L10n.text("ios26.home.action.report_interpretation.title"),
            subtitle: L10n.text("ios26.home.action.report_interpretation.subtitle"),
            symbolName: "doc.text.magnifyingglass",
            prominence: .primary,
            isEnabled: hasMembers,
            actionLabel: L10n.text("ios26.home.action.interpret")
        )
    }

    private var medicationItem: IOS26HomeActionItem {
        IOS26HomeActionItem(
            id: .medication,
            title: L10n.text("ios26.home.action.medication.title"),
            subtitle: L10n.text("ios26.home.action.medication.subtitle"),
            symbolName: "pills.fill",
            prominence: .compact,
            isEnabled: true,
            actionLabel: nil
        )
    }

    private var familyMedicineCabinetItem: IOS26HomeActionItem {
        IOS26HomeActionItem(
            id: .familyMedicineCabinet,
            title: L10n.text("ios26.home.action.family_medicine_cabinet.title"),
            subtitle: L10n.text("ios26.home.action.family_medicine_cabinet.subtitle"),
            symbolName: "cross.case.fill",
            prominence: .compact,
            isEnabled: hasMembers,
            actionLabel: nil
        )
    }

    private var familyArchiveItem: IOS26HomeActionItem {
        IOS26HomeActionItem(
            id: .familyArchive,
            title: L10n.text("ios26.home.action.family_archive.title"),
            subtitle: L10n.text("ios26.home.action.family_archive.subtitle"),
            symbolName: "person.3.fill",
            prominence: .secondary,
            isEnabled: hasMembers,
            actionLabel: nil
        )
    }

  @ViewBuilder
    private func actionCard(for item: IOS26HomeActionItem) -> some View {
        IOS26HomeActionCard(
            item: item,
            isLoading: loadingAction == item.id && isCreatingQuickStartConversation,
            action: {
                guard item.isEnabled else { return }
                triggerHaptic(style: .light)
                if item.id == .checkupPlan || item.id == .reportInterpretation {
                    loadingAction = item.id
                }
                actionHandler.handle(item.id)
            }
        )
    }

    private var isCreatingQuickStartConversation: Bool {
        deepTutorChatViewModel.isCreatingConversation || chatListViewModel.isCreatingQuickStartThread
    }

    @ViewBuilder
    private func compactActionCard(for item: IOS26HomeActionItem) -> some View {
        IOS26HomeActionCard(
            item: item,
            isLoading: false,
            action: {
                guard item.isEnabled else { return }
                triggerHaptic(style: .light)
                actionHandler.handle(item.id)
            }
        )
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}

@available(iOS 26.0, *)
private struct IOS26HomeActionCard: View {
    let item: IOS26HomeActionItem
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: item.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(item.isEnabled ? Color.accentColor : .secondary)
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else if let actionLabel = item.actionLabel {
                        Text(actionLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.isEnabled ? Color.accentColor : .secondary)
                    }
                }
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(item.isEnabled ? .primary : .secondary)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if item.isEnabled == false {
                    Text(L10n.text("ios26.home.action.requires_member"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(item.prominence == .primary ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(item.isEnabled == false || isLoading)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle)
    }
}
