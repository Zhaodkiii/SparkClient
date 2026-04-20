import Foundation

/// 合并「本地目录生成的场景 bundle」与「Pro 远程 bootstrap 仅内存 bundle」。
enum AIRuntimeConfigAssembler {
    /// Pro 某场景若存在非空 `models`，则整包替换该场景；否则保留本地场景包。
    static func merge(
        local: AIScenarioRemoteBundlesCollection,
        pro: AIScenarioRemoteBundlesCollection?
    ) -> AIScenarioRemoteBundlesCollection {
        guard let pro else { return local }
        var merged = local
        for scenario in AIScenario.allCases {
            let remoteBundle = pro.bundle(for: scenario)
            if remoteBundle.models.isEmpty == false {
                merged.setBundle(remoteBundle, for: scenario)
            }
        }
        return merged
    }
}
