import Foundation

/// 将工具执行结果与元数据组装为「数据外传同意」展示载荷（不含 UI 截断策略）。
enum ConsentPayloadBuilder {
    static func makeSharePrompt(
        result: ToolExecutionResult,
        callArguments: String,
        providerCompany: String?,
        modelName: String?,
        endpoint: String?,
        privacyPolicyURL: URL?
    ) -> ExternalToolDataSharePrompt {
        ExternalToolDataSharePrompt(
            id: UUID(),
            providerCompany: (providerCompany ?? "UNKNOWN").uppercased(),
            endpointLine: nonEmpty(endpoint) ?? "-",
            modelLine: nonEmpty(modelName) ?? "-",
            dataLines: [
                "\(SparkToolName.displayName(for: result.toolName)) (\(result.toolName)) - \(result.outputText.count) chars"
            ],
            payloadBlocks: [
                ExternalToolDataSharePayloadBlock(
                    id: UUID(),
                    toolAPIName: result.toolName,
                    friendlyTitle: SparkToolName.displayName(for: result.toolName),
                    argumentsText: callArguments,
                    resultText: result.outputText,
                    fullResultCharCount: result.outputText.count
                )
            ],
            privacyPolicyURL: privacyPolicyURL
        )
    }

    private static func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
