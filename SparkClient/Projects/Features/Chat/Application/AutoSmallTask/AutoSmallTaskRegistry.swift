import Foundation

@MainActor
final class AutoSmallTaskRegistry {
    private let aiConfigCenter: AIConfigCenter
    private let registryStore: UserDefaultsAutoSmallTaskRegistryStore
    private let migrationPlanner: AutoSmallTaskMigrationPlanner
    private let runtimeCapabilityChecker: AutoSmallTaskRuntimeCapabilityChecker
    private let logger: Logger

    init(
        aiConfigCenter: AIConfigCenter,
        registryStore: UserDefaultsAutoSmallTaskRegistryStore = UserDefaultsAutoSmallTaskRegistryStore(),
        migrationPlanner: AutoSmallTaskMigrationPlanner = AutoSmallTaskMigrationPlanner(),
        runtimeCapabilityChecker: AutoSmallTaskRuntimeCapabilityChecker = AutoSmallTaskRuntimeCapabilityChecker(),
        logger: Logger = ConsoleLogger()
    ) {
        self.aiConfigCenter = aiConfigCenter
        self.registryStore = registryStore
        self.migrationPlanner = migrationPlanner
        self.runtimeCapabilityChecker = runtimeCapabilityChecker
        self.logger = logger
    }

    func registerIfNeeded(
        definition: AutoSmallTaskDefinition,
        userID: Int64
    ) async throws -> SmallTask {
        let result = try await registerOrMigrateIfNeeded(
            definition: definition,
            userID: userID
        )
        if let task = result.smallTask, result.isRunnable {
            return task
        }
        throw AutoSmallTaskRegistryError.blocked(result.blockedReason)
    }

    func registerOrMigrateIfNeeded(
        definition: AutoSmallTaskDefinition,
        userID: Int64
    ) async throws -> AutoSmallTaskRegistrationResult {
        logger.info(
            "auto_small_task.migration.plan.start userID=\(userID) businessKey=\(definition.businessKey.rawValue) code=\(definition.smallTaskCode) version=\(definition.definitionVersion) toolContract=\(definition.toolContractVersion)",
            module: .aiConfig
        )

        let snapshot = await aiConfigCenter.currentSnapshot(ownerAccountID: userID)
        let existingByCode = snapshot.smallTasks.first { $0.code == definition.smallTaskCode }
        let registryRecord = registryStore.load(userID: userID, businessKey: definition.businessKey)
        let registryTaskExists = registryRecord.flatMap { record in
            snapshot.smallTasks.first { $0.code == record.smallTaskCode || $0.id == record.localSmallTaskID }
        }
        let existingTask = registryTaskExists ?? existingByCode
        let capability = runtimeCapabilityChecker.currentCapability()
        let decision = migrationPlanner.plan(
            definition: definition,
            registryRecord: registryRecord,
            existingTask: existingTask,
            runtimeCapability: capability
        )

        logger.info(
            "auto_small_task.migration.plan userID=\(userID) businessKey=\(definition.businessKey.rawValue) code=\(definition.smallTaskCode) fromVersion=\(registryRecord?.definitionVersion.description ?? "nil") toVersion=\(definition.definitionVersion) action=\(decision.action.rawValue) reason=\(decision.blockedReason?.rawValue ?? "none")",
            module: .aiConfig
        )

        switch decision {
        case .skip:
            guard let task = existingTask else {
                return try await saveDefinition(
                    definition,
                    userID: userID,
                    targetID: nextLocalSmallTaskID(from: snapshot.smallTasks),
                    registryRecord: registryRecord,
                    action: .inserted,
                    reason: "missing_task_for_existing_registry"
                )
            }
            logger.info(
                "auto_small_task.migration.skip userID=\(userID) businessKey=\(definition.businessKey.rawValue) smallTaskID=\(task.id) version=\(definition.definitionVersion)",
                module: .aiConfig
            )
            return AutoSmallTaskRegistrationResult(
                smallTask: task,
                action: .skipped,
                isRunnable: true,
                blockedReason: nil
            )

        case .insert:
            return try await saveDefinition(
                definition,
                userID: userID,
                targetID: existingTask?.id ?? nextLocalSmallTaskID(from: snapshot.smallTasks),
                registryRecord: registryRecord,
                action: .inserted,
                reason: "missing_registry"
            )

        case .upgrade(let fromVersion, let toVersion):
            return try await saveDefinition(
                definition,
                userID: userID,
                targetID: existingTask?.id ?? nextLocalSmallTaskID(from: snapshot.smallTasks),
                registryRecord: registryRecord,
                action: .upgraded,
                reason: "definition_version_increased_\(fromVersion)_to_\(toVersion)"
            )

        case .hashConflict:
            logger.info(
                "auto_small_task.migration.hash_conflict userID=\(userID) businessKey=\(definition.businessKey.rawValue) code=\(definition.smallTaskCode) fromHash=\(registryRecord?.payloadHash ?? "nil") toHash=\(definition.payloadHash)",
                module: .aiConfig
            )
            return try await saveDefinition(
                definition,
                userID: userID,
                targetID: existingTask?.id ?? nextLocalSmallTaskID(from: snapshot.smallTasks),
                registryRecord: registryRecord,
                action: .hashConflict,
                reason: "definition_hash_changed_without_version_bump"
            )

        case .preserveUserEdited:
            guard let task = existingTask else {
                return try await saveDefinition(
                    definition,
                    userID: userID,
                    targetID: nextLocalSmallTaskID(from: snapshot.smallTasks),
                    registryRecord: registryRecord,
                    action: .inserted,
                    reason: "missing_preserved_task"
                )
            }
            let now = Date()
            registryStore.save(
                makeRecord(
                    userID: userID,
                    definition: definition,
                    localSmallTaskID: task.id,
                    registryRecord: registryRecord,
                    action: .preservedUserEdited,
                    reason: "preserve_user_edited",
                    now: now
                )
            )
            logger.info(
                "auto_small_task.migration.preserve_user_edited userID=\(userID) businessKey=\(definition.businessKey.rawValue) smallTaskID=\(task.id)",
                module: .aiConfig
            )
            return AutoSmallTaskRegistrationResult(
                smallTask: task,
                action: .preservedUserEdited,
                isRunnable: true,
                blockedReason: nil
            )

        case .blocked(let reason):
            logger.info(
                "auto_small_task.migration.blocked userID=\(userID) businessKey=\(definition.businessKey.rawValue) code=\(definition.smallTaskCode) reason=\(reason.rawValue) requiredRuntime=\(definition.minimumRuntimeVersion) currentRuntime=\(capability.runtimeVersion) requiredToolContract=\(definition.toolContractVersion) currentToolContract=\(capability.toolContractVersion)",
                module: .aiConfig
            )
            return .blocked(reason)
        }
    }

    private func saveDefinition(
        _ definition: AutoSmallTaskDefinition,
        userID: Int64,
        targetID: Int,
        registryRecord: AutoSmallTaskRegistryRecord?,
        action: AutoSmallTaskMigrationAction,
        reason: String
    ) async throws -> AutoSmallTaskRegistrationResult {
        let saved = try await aiConfigCenter.upsertLocalSmallTask(
            definition.makeSmallTask(id: targetID),
            ownerAccountID: userID
        )
        let now = Date()
        registryStore.save(
            makeRecord(
                userID: userID,
                definition: definition,
                localSmallTaskID: saved.id,
                registryRecord: registryRecord,
                action: action,
                reason: reason,
                now: now
            )
        )
        logger.info(
            "auto_small_task.migration.\(action.rawValue) userID=\(userID) businessKey=\(definition.businessKey.rawValue) smallTaskID=\(saved.id) version=\(definition.definitionVersion) reason=\(reason)",
            module: .aiConfig
        )
        return AutoSmallTaskRegistrationResult(
            smallTask: saved,
            action: action,
            isRunnable: true,
            blockedReason: nil
        )
    }

    private func makeRecord(
        userID: Int64,
        definition: AutoSmallTaskDefinition,
        localSmallTaskID: Int,
        registryRecord: AutoSmallTaskRegistryRecord?,
        action: AutoSmallTaskMigrationAction,
        reason: String,
        now: Date
    ) -> AutoSmallTaskRegistryRecord {
        AutoSmallTaskRegistryRecord(
            userID: userID,
            businessKey: definition.businessKey,
            smallTaskCode: definition.smallTaskCode,
            localSmallTaskID: localSmallTaskID,
            definitionVersion: definition.definitionVersion,
            minimumRuntimeVersion: definition.minimumRuntimeVersion,
            toolContractVersion: definition.toolContractVersion,
            payloadHash: definition.payloadHash,
            lastMigrationAction: action,
            lastMigrationReason: reason,
            createdAt: registryRecord?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func nextLocalSmallTaskID(from tasks: [SmallTask]) -> Int {
        (tasks.filter { $0.source == .local }.map(\.id).max() ?? 0) + 1
    }
}

nonisolated enum AutoSmallTaskRegistryError: LocalizedError {
    case blocked(AutoSmallTaskMigrationBlockedReason?)

    var errorDescription: String? {
        switch self {
        case .blocked(let reason):
            return "Auto small task registration blocked: \(reason?.rawValue ?? "unknown")"
        }
    }
}
