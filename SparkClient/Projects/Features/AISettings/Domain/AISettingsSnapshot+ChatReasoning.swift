import Foundation

extension AISettingsSnapshot {
    /// Build reasoning capability context for the chat composer’s selected model (or default chat model).
    func chatReasoningContext(selectedModelName: String?) -> ChatModelReasoningContext {
        let name: String = {
            if let n = selectedModelName, n.isEmpty == false { return n }
            return chat.model
        }()
        if let m = allModels.first(where: { $0.name == name }) {
            return ChatModelReasoningContext(
                providerCompany: m.company.uppercased(),
                supportsReasoning: m.supportsReasoning,
                reasoningControllable: m.reasoningControllable
            )
        }
        return .unknown
    }
}
