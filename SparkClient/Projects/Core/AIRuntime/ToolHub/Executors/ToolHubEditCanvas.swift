import Foundation

extension ToolHub {
    func runEditCanvas(invocation: ToolInvocation) -> ToolExecutionResult {
        let title = (invocation.arguments["title"] ?? "默认画布").trimmingCharacters(in: .whitespacesAndNewlines)
        guard canvasStore[title] != nil else {
            return ToolExecutionResult(
                toolName: SparkToolName.editCanvas,
                outputText: "画布不存在：\(title)",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        if let patternsRaw = invocation.arguments["patterns"],
           let replRaw = invocation.arguments["replacements"],
           let pData = patternsRaw.data(using: .utf8),
           let rData = replRaw.data(using: .utf8),
           let patterns = try? JSONSerialization.jsonObject(with: pData) as? [String],
           let replacements = try? JSONSerialization.jsonObject(with: rData) as? [String],
           patterns.count == replacements.count,
           patterns.isEmpty == false {
            var body = canvasStore[title] ?? ""
            for index in patterns.indices {
                guard let regex = try? NSRegularExpression(pattern: patterns[index], options: []) else { continue }
                let range = NSRange(body.startIndex..., in: body)
                body = regex.stringByReplacingMatches(in: body, options: [], range: range, withTemplate: replacements[index])
            }
            canvasStore[title] = body
            return ToolExecutionResult(
                toolName: SparkToolName.editCanvas,
                outputText: "画布已按正则更新：\(title)",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        if let content = invocation.arguments["content"] {
        canvasStore[title] = content
        return ToolExecutionResult(
            toolName: SparkToolName.editCanvas,
                outputText: "画布已整段更新：\(title)",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        return ToolExecutionResult(
            toolName: SparkToolName.editCanvas,
            outputText: "请提供 patterns 与 replacements（与 ZDK 一致的 JSON 数组字符串），或提供 content 进行整段覆盖。",
            sensitive: false,
            shouldBypassModel: true
        )
    }

}
