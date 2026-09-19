import Foundation

/// 对话内工具卡/症状卡等行内输入与底部主 Composer 的焦点协调。
enum ChatInlineInputFocus {
    /// 行内输入（问答卡、症状描述等）获得/失去焦点。
    static let focusChangedNotification = Notification.Name("chat.inlineInput.focusChanged")
    /// 主 Composer 文本区开始编辑（应恢复底部输入模块）。
    static let mainComposerDidBeginEditingNotification = Notification.Name("chat.mainComposer.didBeginEditing")

    static func setInlineInputFocused(_ focused: Bool) {
        NotificationCenter.default.post(
            name: focusChangedNotification,
            object: nil,
            userInfo: ["focused": focused]
        )
    }

    static func notifyMainComposerDidBeginEditing() {
        NotificationCenter.default.post(name: mainComposerDidBeginEditingNotification, object: nil)
    }
}

enum ChatComposerAccessibilityIdentifier {
    static let mainComposerTextView = "chat.mainComposer.textView"
}
