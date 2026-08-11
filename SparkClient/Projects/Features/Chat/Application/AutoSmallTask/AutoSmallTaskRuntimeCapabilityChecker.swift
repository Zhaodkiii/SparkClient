import Foundation

nonisolated struct AutoSmallTaskRuntimeCapabilityChecker: Sendable {
    var runtimeVersion: Int
    var toolContractVersion: Int
    var availableToolNames: Set<String>

    init(
        runtimeVersion: Int = AutoSmallTaskRuntimeVersion.current,
        toolContractVersion: Int = AutoSmallTaskRuntimeVersion.currentToolContract,
        availableToolNames: Set<String> = Set(SparkToolName.all)
    ) {
        self.runtimeVersion = runtimeVersion
        self.toolContractVersion = toolContractVersion
        self.availableToolNames = availableToolNames
    }

    func currentCapability() -> AutoSmallTaskRuntimeCapability {
        AutoSmallTaskRuntimeCapability(
            runtimeVersion: runtimeVersion,
            toolContractVersion: toolContractVersion,
            availableToolNames: availableToolNames
        )
    }
}
