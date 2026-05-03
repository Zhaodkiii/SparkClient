import Foundation

struct MemoryPromptBuilder: Sendable {
    func makePromptSection(results: [MemorySearchResult], locale: Locale = .current) -> String {
        guard results.isEmpty == false else { return "" }
        let isChinese = locale.identifier.lowercased().hasPrefix("zh")
        let lines = results.map { result in
            "- \(result.record.title.isEmpty ? "Memory" : result.record.title): \(result.record.content)"
        }
        if isChinese {
            return """
            # 记忆
            下面是与当前对话可能相关的长期记忆。只有当它确实有助于回答用户时才使用，忽略不相关内容。
            \(lines.joined(separator: "\n"))
            """
        }
        return """
        # Memory
        These long-term memories may be relevant to the current conversation. Use them only when helpful and ignore unrelated items.
        \(lines.joined(separator: "\n"))
        """
    }
}

