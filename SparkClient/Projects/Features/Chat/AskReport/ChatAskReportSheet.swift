import SwiftUI

struct ChatAskReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var memberContextStore: MemberContextStore
    @StateObject private var viewModel: ChatAskReportSheetViewModel

    let boundMemberID: Int
    let pendingRefs: [HealthResourceRef]
    let onAppendToPreview: ([HealthResourceRef]) -> Void
    let onSetMemberBinding: (Int?) -> Void
    let onMaxRefsReached: () -> Void

    init(
        memberContextStore: MemberContextStore,
        boundMemberID: Int,
        pendingRefs: [HealthResourceRef],
        initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        fetchCompleteData: @escaping (Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData,
        onAppendToPreview: @escaping ([HealthResourceRef]) -> Void,
        onSetMemberBinding: @escaping (Int?) -> Void,
        onMaxRefsReached: @escaping () -> Void
    ) {
        self.memberContextStore = memberContextStore
        self.boundMemberID = boundMemberID
        self.pendingRefs = pendingRefs
        self.onAppendToPreview = onAppendToPreview
        self.onSetMemberBinding = onSetMemberBinding
        self.onMaxRefsReached = onMaxRefsReached
        _viewModel = StateObject(
            wrappedValue: ChatAskReportSheetViewModel(
                memberID: boundMemberID,
                pendingRefs: pendingRefs,
                initialCompleteData: initialCompleteData,
                fetchCompleteData: fetchCompleteData
            )
        )
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            VStack(spacing: 0) {
                memberBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                searchField
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                tabBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                contentArea

                appendButton
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .navigationTitle(L10n.text("chat.ask_report.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.close")) { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
        .onAppear {
            viewModel.syncSelectionWithPendingRefs(pendingRefs)
        }
        .onChange(of: pendingRefs.map(\.id)) { _ in
            viewModel.syncSelectionWithPendingRefs(pendingRefs)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView(L10n.text("chat.ask_report.sheet.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(L10n.text("common.retry")) {
                    Task { await viewModel.load() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ChatAskReportTimelineView(
                rows: viewModel.filteredRows,
                searchQuery: viewModel.searchQuery,
                selectedSourceIDs: viewModel.selectedSourceIDs,
                onToggleSelection: { key in
                    if viewModel.toggleSelection(key) == false {
                        onMaxRefsReached()
                    }
                }
            )
        }
    }

    private var memberBar: some View {
        HStack {
            MemberProfileBindingMenu(
                memberContextStore: memberContextStore,
                selectedMemberID: boundMemberID,
                onSelect: { memberID in
                    onSetMemberBinding(memberID)
                    if let memberID, memberID == boundMemberID {
                        viewModel.syncSelectionWithPendingRefs(pendingRefs)
                        Task { await viewModel.reload(for: memberID) }
                    } else if memberID != boundMemberID {
                        dismiss()
                    }
                }
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                    Text(L10n.text("chat.composer.toggle.member_profile"))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(uiColor: .secondarySystemFill)))
            }
            Spacer()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.text("chat.ask_report.sheet.search_placeholder"), text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
        )
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AskReportTab.allCases) { tab in
                    Button {
                        viewModel.selectedTab = tab
                    } label: {
                        Text(L10n.text(tab.localizationKey))
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(viewModel.selectedTab == tab ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var appendButton: some View {
        let max = HealthResourceSendValidator.maxRefs
        let title = String(
            format: L10n.text("chat.ask_report.sheet.add_preview_format"),
            viewModel.selectedCount,
            max
        )
        return Button {
            switch viewModel.appendSelectionToPreview(existingRefs: pendingRefs) {
            case .added(let refs):
                onAppendToPreview(refs)
                dismiss()
            case .nothingToAdd:
                dismiss()
            case .atCapacity:
                onMaxRefsReached()
            }
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.selectedCount == 0)
    }
}
