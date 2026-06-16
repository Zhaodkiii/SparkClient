import UIKit

/// AI 设置页提示词工具：协议注入替代 struct 内存储型 async closure。
@MainActor
protocol AISettingsPromptToolingProviding: AnyObject {
    func autoFillAgentPrompt(displayName: String, baseModelName: String) async throws -> String
    func translate(text: String) async throws -> String
    func ocrImage(_ image: UIImage) async throws -> String
}

@MainActor
final class DefaultAISettingsPromptTooling: AISettingsPromptToolingProviding {
    private let autoFillAgentPromptUseCase: AutoFillAgentPromptUseCase
    private let translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase
    private let ocrKnowledgeImageUseCase: OCRKnowledgeImageUseCase

    init(
        autoFillAgentPromptUseCase: AutoFillAgentPromptUseCase,
        translateKnowledgeTextUseCase: TranslateKnowledgeTextUseCase,
        ocrKnowledgeImageUseCase: OCRKnowledgeImageUseCase
    ) {
        self.autoFillAgentPromptUseCase = autoFillAgentPromptUseCase
        self.translateKnowledgeTextUseCase = translateKnowledgeTextUseCase
        self.ocrKnowledgeImageUseCase = ocrKnowledgeImageUseCase
    }

    func autoFillAgentPrompt(displayName: String, baseModelName: String) async throws -> String {
        try await autoFillAgentPromptUseCase.execute(displayName: displayName, baseModelName: baseModelName)
    }

    func translate(text: String) async throws -> String {
        try await translateKnowledgeTextUseCase.execute(text: text)
    }

    func ocrImage(_ image: UIImage) async throws -> String {
        try await ocrKnowledgeImageUseCase.execute(image: image)
    }
}

@MainActor
final class UnavailableAISettingsPromptTooling: AISettingsPromptToolingProviding {
    nonisolated init() {}

    func autoFillAgentPrompt(displayName: String, baseModelName: String) async throws -> String { "" }
    func translate(text: String) async throws -> String { text }
    func ocrImage(_ image: UIImage) async throws -> String { "" }
}
