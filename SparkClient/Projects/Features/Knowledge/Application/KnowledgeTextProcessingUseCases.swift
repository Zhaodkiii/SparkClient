import Foundation
import UIKit

/// 知识处理 capability 标记：润色 / 翻译 / 自动填充等单次 AI 文本变换。
protocol KnowledgeProcessingCapability: Sendable {
    static var capabilityName: String { get }
}

extension KnowledgeProcessingCapability {
    static var capabilityName: String { "knowledge_processing" }
}

/// 使用 `AIScenario.optimizationText` 润色当前正文（与工具栏「优化」一致）。
struct PolishKnowledgeTextUseCase: Sendable, KnowledgeProcessingCapability {
    let runtime: AIRuntimeServing

    func execute(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return text }

        let request = AIRuntimeTextRequest(
            scenario: .optimizationText,
            messages: [AIRuntimeMessage(role: .user, content: trimmed)]
        )
        return try await collectResponseText(
            from: try await runtime.generateTextStream(request: request)
        )
    }
}

/// 使用聊天场景 + system 提示做翻译（与工具栏「翻译」一致，首版固定译为中文）。
struct TranslateKnowledgeTextUseCase: Sendable, KnowledgeProcessingCapability {
    let runtime: AIRuntimeServing

    func execute(text: String, targetLanguageDescription: String = "中文") async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return text }

        let system = "You are a professional translator. Translate the user's text into \(targetLanguageDescription). Output only the translated text, with no explanations or quotes."
        let request = AIRuntimeTextRequest(
            scenario: .chat,
            messages: [
                AIRuntimeMessage(role: .system, content: system),
                AIRuntimeMessage(role: .user, content: trimmed)
            ]
        )
        return try await collectResponseText(
            from: try await runtime.generateTextStream(request: request)
        )
    }
}

/// 使用 `AIScenario.optimizationText` 为本地智能体自动生成 system prompt。
struct AutoFillAgentPromptUseCase: Sendable, KnowledgeProcessingCapability {
    let runtime: AIRuntimeServing

    func execute(displayName: String, baseModelName: String) async throws -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = baseModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
        请为一个本地智能体生成可直接保存的 system prompt。
        智能体名称：\(name.isEmpty ? "未命名智能体" : name)
        基座模型：\(model.isEmpty ? "未指定" : model)

        要求：
        1. 使用中文。
        2. 明确角色定位、能力边界、交流风格、输出规则和安全约束。
        3. 适合作为系统提示词直接注入模型。
        4. 不要输出解释、标题、引号或 Markdown 包装。
        """

        let request = AIRuntimeTextRequest(
            scenario: .optimizationText,
            messages: [AIRuntimeMessage(role: .user, content: prompt)]
        )
        return try await collectResponseText(
            from: try await runtime.generateTextStream(request: request)
        )
    }
}

/// 从相册/相机图片识别文字并供编辑器追加（与 `OCROrchestrator` 病历能力同源）。
struct OCRKnowledgeImageUseCase: Sendable {
    let ocr: OCROrchestrator

    func execute(image: UIImage) async throws -> String {
        let result = try await ocr.recognize(image: image, options: .medicalDefault)
        return result.text
    }
}

private func collectResponseText(
    from stream: AsyncThrowingStream<AIRuntimeStreamEvent, Error>
) async throws -> String {
    var bufferedText = ""
    var completedText: String?
    for try await event in stream {
        switch event {
        case .textDelta(let delta):
            bufferedText.append(delta)
        case .completed(let response):
            completedText = response.text
        case .reasoningDelta, .toolCallDelta:
            continue
        }
    }
    return completedText ?? bufferedText
}
