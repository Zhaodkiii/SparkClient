import Foundation

/// 兼容旧调用方：返回 domain 级 hint 字符串。
/// 结构化槽位请使用 `DeepTutorToolIntentClassifier`。
enum DeepTutorToolIntentHints: Sendable {
    nonisolated static func detect(in userInput: String, capability: DeepTutorCapability) -> [String] {
        DeepTutorToolIntentClassifier.hintLabels(
            from: DeepTutorToolIntentClassifier.classify(
                userInput: userInput,
                capability: capability
            )
        )
    }
}
