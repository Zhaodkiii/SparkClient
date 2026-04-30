import Foundation

/// 系统提示词解析器
/// 负责按优先级**合并、解析、生成**最终发送给 AI 的系统提示词（System Prompt）
/// 优先级：小任务 > 智能体Prompt > 会话Prompt > 默认Prompt
struct ChatSystemPromptResolver: Sendable {
    /// 默认系统提示词（兜底使用）
    let defaultPrompt: String

    /// 初始化
    /// - Parameter defaultPrompt: 默认提示词，默认从本地化文件读取
    init(defaultPrompt: String = PromptLocalizer().chatSystemPrompt()) {
        self.defaultPrompt = defaultPrompt
    }

    /// 解析并返回最终使用的系统提示词（核心方法）
    /// - Parameters:
    ///   - sessionPrompt: 会话级提示词
    ///   - agentPrompt: 智能体级提示词
    ///   - smallTask: 小任务模型
    /// - Returns: 按优先级计算后的最终系统提示词
    func resolve(
        sessionPrompt: String?,
        agentPrompt: String?,
        smallTask: SmallTask?
    ) -> String {
        let resolved: String
        // 优先级 1：如果有小任务 → 直接使用小任务专用提示词
        if let smallTask {
            resolved = makeSmallTaskSystemPrompt(task: smallTask)
        } else if let agent = normalized(agentPrompt) {
            // 优先级 2：使用智能体提示词（已做空值/空白过滤）
            resolved = agent
        } else if let session = normalized(sessionPrompt) {
            // 优先级 3：使用会话提示词（已做空值/空白过滤）
            resolved = session
        } else {
            // 优先级 4：都没有 → 使用默认提示词
            resolved = defaultPrompt
        }
        return replaceDateKeyword(in: resolved)
    }

    /// 生成小任务专用系统提示词
    /// 格式：【小任务】【简介】【设定】【允许工具】结构化拼接
    private func makeSmallTaskSystemPrompt(task: SmallTask) -> String {
        // 基础模块：任务名称 + 简介 + 任务Prompt
        var blocks = [
            "【小任务】\n\(task.name)",
            "【任务简介】\n\(task.brief.isEmpty ? "无" : task.brief)",
            "【任务设定 / Prompt】\n\(task.prompt)"
        ]
        // 如果有工具列表 → 追加【允许工具】模块
        if task.toolList.isEmpty == false {
            blocks.append("【允许工具】\n\(task.toolList.joined(separator: ", "))")
        }
        // 用双换行拼接所有模块，结构清晰
        return blocks.joined(separator: "\n\n")
    }

    private func replaceDateKeyword(in prompt: String) -> String {
        guard prompt.contains(AIPromptKeywords.currentDate) else { return prompt }
        return prompt.replacingOccurrences(of: AIPromptKeywords.currentDate, with: currentDateInstruction())
    }

    private func currentDateInstruction() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return String(
            format: L10n.text(
                "ai_runtime.prompt.current_date_instruction_format",
                fallback: "Current date: %@. Please use this date to interpret time expressions such as today, tomorrow, and this week.",
                comment: "System prompt instruction with injected current date"
            ),
            formatter.string(from: Date())
        )
    }

    /// 字符串标准化：去首尾空白 + 空串转 nil
    /// 避免空白字符被当作有效提示词
    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
