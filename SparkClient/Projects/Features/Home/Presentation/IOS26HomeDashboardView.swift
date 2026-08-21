import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct IOS26HomeActionItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case checkupPlan
        case reportInterpretation
        case reportUpload
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

//@available(iOS 26.0, *)
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
                if shouldShowTaskSummarySection {
                    taskSummarySection
                }
                HomeMedicalDashboardGridSection(
                    cards: viewModel.dashboard?.medical.cards ?? [],
                    selectedMemberID: viewModel.selectedMemberID,
                    onSelect: handleMedicalDashboardCard,
                    onInterpretReport: { handlePrimaryAction(reportInterpretationItem) },
                    onUploadReport: { handlePrimaryAction(reportUploadItem) }
                )
                primaryActions
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .ignoresSafeArea()
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

    private var shouldShowTaskSummarySection: Bool {
        taskSummary.pendingCount > 0
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

    private var primaryActions: some View {
        HomePrimaryActionSection(
            items: primaryActionItems,
            loadingAction: loadingAction,
            isCreatingQuickStartConversation: isCreatingQuickStartConversation,
            onLoadingFinished: { loadingAction = nil },
            onSelect: handlePrimaryAction,
            footerItem: familyArchiveItem
        )
    }

    private var primaryActionItems: [IOS26HomeActionItem] {
        [
            checkupPlanItem,
            reportInterpretationItem,
            reportUploadItem
        ]
    }

    private func handleMedicalDashboardCard(_ kind: HomeDashboard.MedicalCard.Kind) {
        switch kind {
        case .medication:
            actionHandler.handle(.medication)
        case .familyMedicineCabinet:
            actionHandler.handle(.familyMedicineCabinet)
        default:
            viewModel.logMedicalListNavigation(kind: kind)
            triggerHaptic(style: .light)
            actionHandler.routeStore.route(to: .homeMedicalList(kind.homeMedicalListRoute, nil))
        }
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

    private var reportUploadItem: IOS26HomeActionItem {
        IOS26HomeActionItem(
            id: .reportUpload,
            title: L10n.text("ios26.home.action.report_upload.title", fallback: "上传报告"),
            subtitle: L10n.text("ios26.home.action.report_upload.subtitle", fallback: "直接进入报告上传与识别页面"),
            symbolName: "square.and.arrow.up.on.square",
            prominence: .primary,
            isEnabled: hasMembers,
            actionLabel: L10n.text("ios26.home.action.start")
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

    private func handlePrimaryAction(_ item: IOS26HomeActionItem) {
        guard item.isEnabled else { return }
        triggerHaptic(style: .light)
        if item.id == .checkupPlan || item.id == .reportInterpretation {
            loadingAction = item.id
        }
        actionHandler.handle(item.id)
    }

    private var isCreatingQuickStartConversation: Bool {
        deepTutorChatViewModel.isCreatingConversation || chatListViewModel.isCreatingQuickStartThread
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}
