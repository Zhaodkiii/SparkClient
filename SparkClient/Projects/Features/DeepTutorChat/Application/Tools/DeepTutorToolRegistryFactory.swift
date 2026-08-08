import Foundation

enum DeepTutorToolRegistryFactory {
    static func makePhase1Registry(
        loadMemoryArchiveUseCase: LoadMemoryArchiveUseCase,
        saveMemoryUseCase: SaveMemoryUseCase,
        updateMemoryUseCase: UpdateMemoryUseCase
    ) -> DeepTutorToolRegistry {
        DeepTutorToolRegistry(
            tools: [
                DeepTutorAskUserTool(),
                DeepTutorGetCurrentMemberBindingTool(),
                DeepTutorMemberSelectionTool(),
                DeepTutorReadMemoryTool(loadUseCase: loadMemoryArchiveUseCase),
                DeepTutorWriteMemoryTool(
                    saveUseCase: saveMemoryUseCase,
                    updateUseCase: updateMemoryUseCase
                ),
            ]
        )
    }
}
