import Foundation

struct ChatThreadGenerationSettings: Equatable, Sendable {
    var currentModelName: String?
    var temperature: Double
    var topP: Double
    var maxTokens: Int
    var maxMessages: Int
    var rolePrompt: String
    var imageDeliveryMode: ChatThreadImageDeliveryMode

    init(
        currentModelName: String?,
        temperature: Double,
        topP: Double,
        maxTokens: Int,
        maxMessages: Int,
        rolePrompt: String,
        imageDeliveryMode: ChatThreadImageDeliveryMode
    ) {
        // 保持线程模型名原值，避免在高频 UI 状态切换时对潜在失效字符串再次做 Foundation 裁剪。
        self.currentModelName = currentModelName
        self.temperature = min(max(temperature, 0.1), 2.0)
        self.topP = min(max(topP, 0.1), 1.0)
        self.maxTokens = max(maxTokens, 16)
        self.maxMessages = max(maxMessages, 1)
        self.rolePrompt = rolePrompt
        self.imageDeliveryMode = imageDeliveryMode
    }

    init(thread: ChatThread) {
        self.init(
            currentModelName: thread.currentModelName,
            temperature: thread.temperature,
            topP: thread.topP,
            maxTokens: thread.maxTokens,
            maxMessages: thread.maxMessages,
            rolePrompt: thread.rolePrompt,
            imageDeliveryMode: thread.imageDeliveryMode
        )
    }
}
