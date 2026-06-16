import Foundation

/// actor 包装：Representable 持有 class 引用，避免 iOS 16 元数据反射 actor 字段。
@MainActor
final class ChatMessageActionStateHandle {
    let state: ChatMessageActionState

    init(_ state: ChatMessageActionState) {
        self.state = state
    }
}
