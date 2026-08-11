import Foundation

@MainActor
final class AutoSmallTaskRegistry {
    private let aiConfigCenter: AIConfigCenter
    private let registryStore: UserDefaultsAutoSmallTaskRegistryStore
    private let logger: Logger

    init(
        aiConfigCenter: AIConfigCenter,
        registryStore: UserDefaultsAutoSmallTaskRegistryStore = UserDefaultsAutoSmallTaskRegistryStore(),
        logger: Logger = ConsoleLogger()
    ) {
        self.aiConfigCenter = aiConfigCenter
        self.registryStore = registryStore
        self.logger = logger
    }

    func registerIfNeeded(
        definition: AutoSmallTaskDefinition,
        userID: Int64
    ) async throws -> SmallTask {
        logger.info(
            "auto_small_task.register.start userID=\(userID) businessKey=\(definition.businessKey.rawValue) code=\(definition.smallTaskCode)",
            module: .aiConfig
        )

        let snapshot = await aiConfigCenter.currentSnapshot(ownerAccountID: userID)
        let existingByCode = snapshot.smallTasks.first { $0.code == definition.smallTaskCode }
        let registryRecord = registryStore.load(userID: userID, businessKey: definition.businessKey)
        let registryMatchesPayload = registryRecord?.payloadVersion == definition.payloadVersion
            && registryRecord?.payloadHash == definition.payloadHash
        let registryTaskExists = registryRecord.flatMap { record in
            snapshot.smallTasks.first { $0.code == record.smallTaskCode || $0.id == record.localSmallTaskID }
        }

        if let task = registryTaskExists ?? existingByCode,
           registryMatchesPayload,
           task.name == definition.name,
           task.brief == definition.brief,
           task.prompt == definition.prompt,
           task.icon == definition.icon,
           task.toolList == definition.toolList {
            logger.info(
                "auto_small_task.register.reuse userID=\(userID) businessKey=\(definition.businessKey.rawValue) smallTaskID=\(task.id)",
                module: .aiConfig
            )
            return task
        }

        let targetID = registryTaskExists?.id
            ?? existingByCode?.id
            ?? nextLocalSmallTaskID(from: snapshot.smallTasks)
        let saved = try await aiConfigCenter.upsertLocalSmallTask(
            definition.makeSmallTask(id: targetID),
            ownerAccountID: userID
        )
        let now = Date()
        registryStore.save(
            AutoSmallTaskRegistryRecord(
                userID: userID,
                businessKey: definition.businessKey,
                smallTaskCode: definition.smallTaskCode,
                localSmallTaskID: saved.id,
                payloadVersion: definition.payloadVersion,
                payloadHash: definition.payloadHash,
                createdAt: registryRecord?.createdAt ?? now,
                updatedAt: now
            )
        )
        logger.info(
            "auto_small_task.register.created userID=\(userID) businessKey=\(definition.businessKey.rawValue) smallTaskID=\(saved.id) payloadVersion=\(definition.payloadVersion)",
            module: .aiConfig
        )
        return saved
    }

    private func nextLocalSmallTaskID(from tasks: [SmallTask]) -> Int {
        (tasks.filter { $0.source == .local }.map(\.id).max() ?? 0) + 1
    }
}
