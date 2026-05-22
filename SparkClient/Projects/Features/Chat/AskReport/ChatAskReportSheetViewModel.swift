import Combine
import Foundation

@MainActor
final class ChatAskReportSheetViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum AppendPreviewResult: Equatable {
        case added([HealthResourceRef])
        case nothingToAdd
        case atCapacity
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published var selectedTab: AskReportTab = .all
    @Published var searchText: String = ""
    /// 当前勾选（含预览区已存在的资料，重开 Sheet 时与 `pendingRefs` 同步）。
    @Published var selectedSourceIDs: Set<String> = []
    @Published private(set) var mappedTimeline: AskReportMappedTimeline?

    let memberID: Int
    let maxPreviewCount: Int

    private let fetchCompleteData: (Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData
    private let initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    private var syncedPendingKeys: Set<String> = []

    init(
        memberID: Int,
        pendingRefs: [HealthResourceRef],
        maxPreviewCount: Int = HealthResourceSendValidator.maxRefs,
        initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        fetchCompleteData: @escaping (Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        self.memberID = memberID
        self.maxPreviewCount = maxPreviewCount
        self.initialCompleteData = initialCompleteData?.memberId == memberID ? initialCompleteData : nil
        self.fetchCompleteData = fetchCompleteData
        let keys = Self.selectionKeys(from: pendingRefs)
        selectedSourceIDs = keys
        syncedPendingKeys = keys
    }

    var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredRows: [AskReportTimelineRow] {
        guard let mappedTimeline else { return [] }
        let base = mappedTimeline.rows(for: selectedTab)
        let query = searchQuery
        guard query.isEmpty == false else { return base }
        return base.compactMap { filterRow($0, query: query) }
    }

    var hasAnyData: Bool {
        guard let mappedTimeline else { return false }
        return mappedTimeline.allRows.isEmpty == false
    }

    var selectedCount: Int {
        selectedSourceIDs.count
    }

    func load() async {
        if let initialCompleteData {
            applyCompleteData(initialCompleteData)
            loadState = .loaded
            Task { await refreshRemote() }
            return
        }
        await refreshRemote()
    }

    func reload(for newMemberID: Int) async {
        guard newMemberID == memberID else { return }
        await refreshRemote()
    }

    func syncSelectionWithPendingRefs(_ refs: [HealthResourceRef]) {
        let pendingKeys = Self.selectionKeys(from: refs)
        let removedFromPreview = syncedPendingKeys.subtracting(pendingKeys)
        selectedSourceIDs.subtract(removedFromPreview)
        selectedSourceIDs.formUnion(pendingKeys)
        syncedPendingKeys = pendingKeys
        enforceSelectionLimit()
    }

    private func enforceSelectionLimit() {
        guard selectedSourceIDs.count > maxPreviewCount else { return }
        var kept = syncedPendingKeys
        let extras = selectedSourceIDs.subtracting(syncedPendingKeys)
        let room = max(0, maxPreviewCount - kept.count)
        kept.formUnion(extras.prefix(room))
        selectedSourceIDs = kept
    }

    func toggleSelection(_ selectionKey: String) -> Bool {
        if selectedSourceIDs.contains(selectionKey) {
            selectedSourceIDs.remove(selectionKey)
            return true
        }
        guard selectedSourceIDs.count < maxPreviewCount else { return false }
        selectedSourceIDs.insert(selectionKey)
        return true
    }

    func isSelected(_ selectionKey: String) -> Bool {
        selectedSourceIDs.contains(selectionKey)
    }

    func refsToAppend(existingRefs: [HealthResourceRef]) -> [HealthResourceRef] {
        let existingIDs = Set(existingRefs.map(\.id))
        return selectedSourceIDs.compactMap { key in
            guard existingIDs.contains(key) == false else { return nil }
            guard let source = selectableSource(for: key) else { return nil }
            return ChatAskReportTimelineMapper.makeHealthResourceRef(from: source)
        }
    }

    func appendSelectionToPreview(existingRefs: [HealthResourceRef]) -> AppendPreviewResult {
        let newRefs = refsToAppend(existingRefs: existingRefs)
        guard newRefs.isEmpty == false else { return .nothingToAdd }
        guard existingRefs.count + newRefs.count <= maxPreviewCount else { return .atCapacity }
        return .added(newRefs)
    }

    func selectableSource(for selectionKey: String) -> ChatSelectableHealthSource? {
        mappedTimeline?.allSelectableSources.first(where: { $0.selectionKey == selectionKey })
    }

    private func refreshRemote() async {
        loadState = .loading
        do {
            let data = try await fetchCompleteData(memberID)
            applyCompleteData(data)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func applyCompleteData(_ data: SparkMedicalSyncAPI.RemoteMemberCompleteData) {
        mappedTimeline = ChatAskReportTimelineMapper.map(data)
    }

    private static func selectionKeys(from refs: [HealthResourceRef]) -> Set<String> {
        Set(refs.map(\.id))
    }

    private func filterRow(_ row: AskReportTimelineRow, query: String) -> AskReportTimelineRow? {
        switch row {
        case .medicalCaseGroup(let parent):
            let parentMatches = matches(parent, query: query)
            let matchingChildren = parent.children.filter { matches($0, query: query) }
            if parentMatches {
                return .medicalCaseGroup(parent)
            }
            if matchingChildren.isEmpty == false {
                return .medicalCaseGroup(parent.replacingChildren(matchingChildren))
            }
            return nil
        case .leaf(let leaf):
            return matches(leaf, query: query) ? row : nil
        }
    }

    private func matches(_ source: ChatSelectableHealthSource, query: String) -> Bool {
        let normalized = query.lowercased()
        if source.searchText.contains(normalized) { return true }
        if source.title.localizedCaseInsensitiveContains(query) { return true }
        if let subtitle = source.subtitle, subtitle.localizedCaseInsensitiveContains(query) { return true }
        if let summary = source.summary, summary.localizedCaseInsensitiveContains(query) { return true }
        return source.badges.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
