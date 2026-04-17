import Foundation

extension AISettingsSnapshot {
    /// 当前对话模型是否支持多模态，以及厂商标识（用于网关单点编码）。
    func chatMultimodalCapabilities(selectedModelName: String?) -> (supportsMultimodal: Bool, providerCompanyUppercased: String?) {
        let name: String = {
            if let n = selectedModelName, n.isEmpty == false { return n }
            return chat.model
        }()
        if let m = allModels.first(where: { $0.name == name }) {
            return (m.supportsMultimodal, m.company.uppercased())
        }
        return (false, nil)
    }
}
