import Combine
import Foundation

@MainActor
final class ChatHealthResourcePreviewViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded(ChatHealthResourcePreviewContent)
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published var expandedDetailGroupIDs: Set<String> = []

    let ref: HealthResourceRef

    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let memberContextStore: MemberContextStore
    private let cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    private let memberCompleteDataFetcher: (any MemberCompleteDataFetching)?

    init(
        ref: HealthResourceRef,
        medicalQueryAPI: SparkMedicalQueryAPI,
        memberContextStore: MemberContextStore,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        memberCompleteDataFetcher: (any MemberCompleteDataFetching)? = nil
    ) {
        self.ref = ref
        self.medicalQueryAPI = medicalQueryAPI
        self.memberContextStore = memberContextStore
        self.cachedCompleteData = cachedCompleteData?.memberId == ref.memberID ? cachedCompleteData : nil
        self.memberCompleteDataFetcher = memberCompleteDataFetcher
    }

    var memberDisplayName: String? {
        memberContextStore.context.members.first(where: { $0.id == ref.memberID })?.name
    }

    var allDetailGroupsExpanded: Bool {
        guard case .loaded(let content) = loadState else { return false }
        let ids = Set(content.detailGroups.map(\.id))
        return ids.isEmpty == false && expandedDetailGroupIDs.isSuperset(of: ids)
    }

    func load() async {
        loadState = .loading
        if let content = await ChatHealthResourcePreviewLoader.load(
            ref: ref,
            medicalQueryAPI: medicalQueryAPI,
            memberName: memberDisplayName,
            cachedCompleteData: cachedCompleteData,
            memberCompleteDataFetcher: memberCompleteDataFetcher
        ) {
            loadState = .loaded(content)
            expandedDetailGroupIDs = Set(content.detailGroups.map(\.id))
        } else {
            loadState = .failed(L10n.text("chat.ask_report.preview.load_failed"))
        }
    }

    func toggleAllDetailGroups() {
        guard case .loaded(let content) = loadState else { return }
        let ids = Set(content.detailGroups.map(\.id))
        if expandedDetailGroupIDs.isSuperset(of: ids) {
            expandedDetailGroupIDs.removeAll()
        } else {
            expandedDetailGroupIDs = ids
        }
    }

    func toggleDetailGroup(_ id: String) {
        if expandedDetailGroupIDs.contains(id) {
            expandedDetailGroupIDs.remove(id)
        } else {
            expandedDetailGroupIDs.insert(id)
        }
    }
}
