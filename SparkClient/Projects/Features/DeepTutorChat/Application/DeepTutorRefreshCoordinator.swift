import Combine
import Foundation

@MainActor
final class DeepTutorRefreshCoordinator: ObservableObject, DeepTutorMessageListRefreshHandling {
    let conversationID: UUID
    private weak var viewModel: DeepTutorChatViewModel?
    @Published private(set) var layoutNonce: UInt64 = 0

    init(conversationID: UUID, viewModel: DeepTutorChatViewModel) {
        self.conversationID = conversationID
        self.viewModel = viewModel
    }

    func refreshMessageList() async {
        await viewModel?.reloadMessages(for: conversationID, forceFullRediff: true)
        layoutNonce += 1
    }
}

@MainActor
protocol DeepTutorMessageListRefreshHandling: AnyObject {
    func refreshMessageList() async
}
