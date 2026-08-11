import Foundation

nonisolated struct AutoSmallTaskMigrationPlanner: Sendable {
    func plan(
        definition: AutoSmallTaskDefinition,
        registryRecord: AutoSmallTaskRegistryRecord?,
        existingTask: SmallTask?,
        runtimeCapability: AutoSmallTaskRuntimeCapability
    ) -> AutoSmallTaskMigrationDecision {
        if let blockedReason = runtimeCapability.supports(definition) {
            return .blocked(reason: blockedReason)
        }

        guard let registryRecord else {
            return .insert
        }

        if registryRecord.definitionVersion > definition.definitionVersion {
            return .blocked(reason: .localVersionNewerThanBundle)
        }

        if registryRecord.definitionVersion < definition.definitionVersion {
            if definition.migrationPolicy == .preserveUserEdited,
               existingTask != nil,
               taskMatchesDefinition(existingTask, definition: definition) == false {
                return .preserveUserEdited
            }
            return .upgrade(
                fromVersion: registryRecord.definitionVersion,
                toVersion: definition.definitionVersion
            )
        }

        if registryRecord.payloadHash == definition.payloadHash,
           taskMatchesDefinition(existingTask, definition: definition) {
            return .skip
        }

        if registryRecord.payloadHash != definition.payloadHash {
            if definition.migrationPolicy == .forceOverwrite {
                return .hashConflict
            }
            if shouldPreserveUserEditedTask(
                policy: definition.migrationPolicy,
                registryRecord: registryRecord,
                existingTask: existingTask,
                definition: definition
            ) {
                return .preserveUserEdited
            }
            return .hashConflict
        }

        return .upgrade(
            fromVersion: registryRecord.definitionVersion,
            toVersion: definition.definitionVersion
        )
    }

    private func shouldPreserveUserEditedTask(
        policy: AutoSmallTaskMigrationPolicy,
        registryRecord: AutoSmallTaskRegistryRecord,
        existingTask: SmallTask?,
        definition: AutoSmallTaskDefinition
    ) -> Bool {
        switch policy {
        case .forceOverwrite:
            return false
        case .preserveUserEdited:
            return existingTask != nil && taskMatchesDefinition(existingTask, definition: definition) == false
        case .overwriteBuiltInOnly:
            guard let existingTask else { return false }
            return registryRecord.payloadHash != definition.payloadHash
                && taskMatchesDefinition(existingTask, definition: definition) == false
        }
    }

    private func taskMatchesDefinition(_ task: SmallTask?, definition: AutoSmallTaskDefinition) -> Bool {
        guard let task else { return false }
        return task.code == definition.smallTaskCode
            && task.name == definition.name
            && task.brief == definition.brief
            && task.prompt == definition.prompt
            && task.icon == definition.icon
            && task.toolList == definition.toolList
    }
}
