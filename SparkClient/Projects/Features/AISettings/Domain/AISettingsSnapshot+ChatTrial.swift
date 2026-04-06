import Foundation

extension AISettingsSnapshot {
    /// `trialModelPolicy` 中对话场景的模型 id 列表（去重、排序）。
    func chatTrialPolicyModelNames() -> [String] {
        let names = trialModelPolicy.filter { $0.scenario == .chat }.map { $0.config.model }
        return Array(Set(names)).sorted()
    }

    /// 对话输入栏将来拉取候选模型时调用：试用期内若该 id 属于 chat 试用策略，则受「模型设置」页 Toggle 约束。
    func shouldOfferTrialModelInChatPicker(modelName: String) -> Bool {
        guard trial.isActive else { return true }
        let trialChat = Set(chatTrialPolicyModelNames())
        guard trialChat.contains(modelName) else { return true }
        return trialChatPickerDisabledModelNames.contains(modelName) == false
    }

    /// 服务端试用策略变更后，移除已不在策略中的禁用项。
    mutating func pruneTrialChatPickerDisabledNames() {
        let valid = Set(chatTrialPolicyModelNames())
        trialChatPickerDisabledModelNames = trialChatPickerDisabledModelNames.filter { valid.contains($0) }
    }
}
