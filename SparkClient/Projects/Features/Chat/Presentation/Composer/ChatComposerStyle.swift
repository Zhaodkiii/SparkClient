import Foundation

/// 聊天输入栏外观：`signal` 为现有简洁条；`hanlin` 为模型行 + 能力开关 + 输入区。
enum ChatComposerStyle: String, CaseIterable, Sendable {
    case signal
    case hanlin

    static let appStorageKey = "chat.composerStyle"
}
