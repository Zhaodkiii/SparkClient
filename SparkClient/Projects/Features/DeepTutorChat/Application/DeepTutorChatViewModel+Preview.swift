import Foundation

extension DeepTutorChatViewModel {
    static func preview(repository: any DeepTutorLocalChatRepository) -> DeepTutorChatViewModel {
        let container = AppContainer.preview
        return DeepTutorChatViewModel(
            repository: repository,
            chatOrchestrator: container.chatOrchestrator,
            aiConfigCenter: container.aiConfigCenter,
            toolInteractionCoordinator: container.toolInteractionCoordinator,
            memberContextStore: container.memberContextStore,
            fileTransferService: container.fileTransferService,
            logger: container.logger
        )
    }
}
