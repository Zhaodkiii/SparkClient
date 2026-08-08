import Foundation

extension DeepTutorChatViewModel {
    static func preview(repository: any DeepTutorLocalChatRepository) -> DeepTutorChatViewModel {
        let container = AppContainer.preview
        return DeepTutorChatViewModel(
            repository: repository,
            chatOrchestrator: container.chatOrchestrator,
            aiRuntimeService: container.aiRuntimeService,
            aiConfigCenter: container.aiConfigCenter,
            loadMemoryArchiveUseCase: container.loadMemoryArchiveUseCase,
            saveMemoryUseCase: container.saveMemoryUseCase,
            updateMemoryUseCase: container.updateMemoryUseCase,
            memberContextStore: container.memberContextStore,
            medicalQueryAPI: container.backend.medicalQuery,
            fileTransferService: container.fileTransferService,
            logger: container.logger
        )
    }
}
