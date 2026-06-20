import UIKit
import SwiftUI

/// 键盘收起工具：统一封装，便于列表拖拽与发送消息后复用。
enum KeyboardDismissHelper {
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    /// 使用系统交互式收键盘。
    func chatScrollDismissesKeyboardInteractively() -> some View {
        self.scrollDismissesKeyboard(.interactively)
    }
}
