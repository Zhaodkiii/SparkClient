import Foundation

enum DeepTutorToolRegistryFactory {
    static func makePhase1Registry(
        loadMemoryArchiveUseCase: LoadMemoryArchiveUseCase,
        saveMemoryUseCase: SaveMemoryUseCase,
        updateMemoryUseCase: UpdateMemoryUseCase,
        memberProfileDataSource: any DeepTutorMemberProfileToolDataSource
    ) -> DeepTutorToolRegistry {
        DeepTutorToolRegistry(
            tools: [
                DeepTutorAskUserTool(),
                DeepTutorGetCurrentMemberBindingTool(),
                DeepTutorQueryMemberProfileTool(dataSource: memberProfileDataSource),
                DeepTutorMemberSelectionTool(),
                DeepTutorReadMemoryTool(loadUseCase: loadMemoryArchiveUseCase),
                DeepTutorShowCustomMessageCardTool(),
                DeepTutorWriteMemoryTool(
                    saveUseCase: saveMemoryUseCase,
                    updateUseCase: updateMemoryUseCase
                ),
            ]
        )
    }
}
