import Foundation

/// 单块工具数据在同意弹窗/内联卡中的展示（完整文本由 UI 决定是否截断）。
struct ExternalToolDataSharePayloadBlock: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let toolAPIName: String
    let friendlyTitle: String
    let argumentsText: String
    let resultText: String
    let fullResultCharCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case toolAPIName
        case friendlyTitle
        case argumentsText
        case resultText
        case fullResultCharCount
        case argumentsDisplay
        case resultDisplay
        case argumentsTruncated
        case resultTruncated
    }

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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        toolAPIName = try c.decode(String.self, forKey: .toolAPIName)
        friendlyTitle = try c.decode(String.self, forKey: .friendlyTitle)
        if let args = try c.decodeIfPresent(String.self, forKey: .argumentsText) {
            argumentsText = args
        } else {
            argumentsText = try c.decode(String.self, forKey: .argumentsDisplay)
        }
        if let res = try c.decodeIfPresent(String.self, forKey: .resultText) {
            resultText = res
        } else {
            resultText = try c.decode(String.self, forKey: .resultDisplay)
        }
        fullResultCharCount = try c.decodeIfPresent(Int.self, forKey: .fullResultCharCount) ?? resultText.count
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(toolAPIName, forKey: .toolAPIName)
        try c.encode(friendlyTitle, forKey: .friendlyTitle)
        try c.encode(argumentsText, forKey: .argumentsText)
        try c.encode(resultText, forKey: .resultText)
        try c.encode(fullResultCharCount, forKey: .fullResultCharCount)
    }
}

struct ExternalToolDataSharePrompt: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let providerCompany: String
    let endpointLine: String
    let modelLine: String
    let dataLines: [String]
    let payloadBlocks: [ExternalToolDataSharePayloadBlock]
    let privacyPolicyURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case providerCompany
        case endpointLine
        case modelLine
        case dataLines
        case payloadBlocks
        case privacyPolicyURL
    }
}
