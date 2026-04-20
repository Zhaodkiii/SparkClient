import Foundation

extension AIScenarioRemoteBundlesCollection {
    /// 输入栏推理能力展示：以场景 bundle 行为准。
    func chatReasoningContext(selectedModelName: String?) -> ChatModelReasoningContext {
        let preferred = selectedModelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let row = resolveRow(for: .chat, preferredModelName: preferred) else {
            return .unknown
        }
        return ChatModelReasoningContext(
            providerCompany: row.company.uppercased(),
            supportsReasoning: row.supportsReasoning,
            reasoningControllable: row.reasoningControllable
        )
    }

    /// 对话多模态及厂商（用于图片送达策略）。
    func chatMultimodalCapabilities(selectedModelName: String?) -> (supportsMultimodal: Bool, providerCompanyUppercased: String?) {
        let preferred = selectedModelName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let row = resolveRow(for: .chat, preferredModelName: preferred) else {
            return (false, nil)
        }
        let company = row.company.trimmingCharacters(in: .whitespacesAndNewlines)
        return (row.supportsMultimodal, company.isEmpty ? nil : company.uppercased())
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
