import Foundation

nonisolated struct AutoSmallTaskRuntimeCapability: Equatable, Sendable {
    let runtimeVersion: Int
    let toolContractVersion: Int
    let availableToolNames: Set<String>

    init(
        runtimeVersion: Int,
        toolContractVersion: Int,
        availableToolNames: Set<String>
    ) {
        self.runtimeVersion = runtimeVersion
        self.toolContractVersion = toolContractVersion
        self.availableToolNames = Set(availableToolNames.map(Self.normalize))
    }

    func supports(_ definition: AutoSmallTaskDefinition) -> AutoSmallTaskMigrationBlockedReason? {
        if runtimeVersion < definition.minimumRuntimeVersion {
            return .runtimeVersionTooLow
        }
        if toolContractVersion < definition.toolContractVersion {
            return .toolContractVersionTooLow
        }
        let requiredTools = Set(definition.toolList.map(Self.normalize))
        if requiredTools.isSubset(of: availableToolNames) == false {
            return .missingRequiredTools
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

nonisolated enum AutoSmallTaskRuntimeVersion {
    static let current = 1
    static let currentToolContract = 2
}
