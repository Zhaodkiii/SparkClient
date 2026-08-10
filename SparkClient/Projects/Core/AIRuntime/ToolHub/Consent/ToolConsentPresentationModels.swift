import Foundation

/// 单块工具数据在同意弹窗/内联卡中的展示（完整文本由 UI 决定是否截断）。
nonisolated struct ExternalToolDataSharePayloadBlock: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let toolAPIName: String
    let friendlyTitle: String
    let argumentsText: String
    let resultText: String
    let fullResultCharCount: Int


    init(
        id: UUID,
        toolAPIName: String,
        friendlyTitle: String,
        argumentsText: String,
        resultText: String,
        fullResultCharCount: Int
    ) {
        self.id = id
        self.toolAPIName = toolAPIName
        self.friendlyTitle = friendlyTitle
        self.argumentsText = argumentsText
        self.resultText = resultText
        self.fullResultCharCount = fullResultCharCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodableKey.self)
        id = try c.decode(UUID.self, forKey: .key("id"))
        toolAPIName = try c.decode(String.self, forKey: .key("toolApiName"))
        friendlyTitle = try c.decode(String.self, forKey: .key("friendlyTitle"))
        if let args = try c.decodeIfPresent(String.self, forKey: .key("argumentsText")) {
            argumentsText = args
        } else {
            argumentsText = try c.decode(String.self, forKey: .key("argumentsDisplay"))
        }
        if let res = try c.decodeIfPresent(String.self, forKey: .key("resultText")) {
            resultText = res
        } else {
            resultText = try c.decode(String.self, forKey: .key("resultDisplay"))
        }
        fullResultCharCount = try c.decodeIfPresent(Int.self, forKey: .key("fullResultCharCount")) ?? resultText.count
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodableKey.self)
        try c.encode(id, forKey: .key("id"))
        try c.encode(toolAPIName, forKey: .key("toolApiName"))
        try c.encode(friendlyTitle, forKey: .key("friendlyTitle"))
        try c.encode(argumentsText, forKey: .key("argumentsText"))
        try c.encode(resultText, forKey: .key("resultText"))
        try c.encode(fullResultCharCount, forKey: .key("fullResultCharCount"))
    }
}

nonisolated struct ExternalToolDataSharePrompt: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let providerCompany: String
    let endpointLine: String
    let modelLine: String
    let dataLines: [String]
    let payloadBlocks: [ExternalToolDataSharePayloadBlock]
    let privacyPolicyURL: URL?

}
