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
    /// iOS 16+ 使用系统交互式收键盘；低版本保持原行为，避免可用性问题。
    @ViewBuilder
    func chatScrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
