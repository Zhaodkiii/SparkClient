import Foundation
import UIKit

/// 使用 `AIScenario.optimizationText` 润色当前正文（与工具栏「优化」一致）。
struct PolishKnowledgeTextUseCase: Sendable {
    let runtime: AIRuntimeServing

    func execute(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return text }

        let request = AIRuntimeTextRequest(
            scenario: .optimizationText,
            messages: [AIRuntimeMessage(role: .user, content: trimmed)]
        )
        let response = try await runtime.generateText(request: request)
        return response.text
    }
}

/// 使用聊天场景 + system 提示做翻译（与工具栏「翻译」一致，首版固定译为中文）。
struct TranslateKnowledgeTextUseCase: Sendable {
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
        let response = try await runtime.generateText(request: request)
        return response.text
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
