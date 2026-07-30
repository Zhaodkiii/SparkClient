import Foundation

protocol AIRemoteConfigProvider: Sendable {
    func fetchRemotePatch() async throws -> AIRemoteSettingsPatch
}

struct AIRemoteSettingsPatch: Equatable, Sendable {
    var revision: String?
    /// Pro 专属场景模型（仅内存，不落库）。
    var scenarioRemoteBundles: AIScenarioRemoteBundlesCollection?
    var smallTasks: [SmallTask]

    init(
        revision: String? = nil,
        scenarioRemoteBundles: AIScenarioRemoteBundlesCollection? = nil,
        smallTasks: [SmallTask] = []
    ) {
        self.revision = revision
        self.scenarioRemoteBundles = scenarioRemoteBundles
        self.smallTasks = smallTasks
    }
}

