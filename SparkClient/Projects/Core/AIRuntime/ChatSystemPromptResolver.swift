import Foundation

struct ChatSystemPromptResolver: Sendable {
    let defaultPrompt: String

    init(defaultPrompt: String = PromptLocalizer().chatSystemPrompt()) {
        self.defaultPrompt = defaultPrompt
    }

    func resolve(
        sessionPrompt: String?,
        agentPrompt: String?,
        smallTask: SmallTask?
    ) -> String {
        if let smallTask {
            return makeSmallTaskSystemPrompt(task: smallTask)
        }
        if let agent = normalized(agentPrompt) {
            return agent
        }
        if let session = normalized(sessionPrompt) {
            return session
        }
        return defaultPrompt
    }

    private func makeSmallTaskSystemPrompt(task: SmallTask) -> String {
        var blocks = [
            "【小任务】\n\(task.name)",
            "【任务简介】\n\(task.brief.isEmpty ? "无" : task.brief)",
            "【任务设定 / Prompt】\n\(task.prompt)"
        ]
        if task.toolList.isEmpty == false {
            blocks.append("【允许工具】\n\(task.toolList.joined(separator: ", "))")
        }
        return blocks.joined(separator: "\n\n")
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
