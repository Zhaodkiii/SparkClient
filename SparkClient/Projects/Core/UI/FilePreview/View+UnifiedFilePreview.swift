import SwiftUI

// MARK: - View 扩展
/// 为 SwiftUI View 扩展统一文件预览弹窗功能
extension View {
    
    /// 统一文件预览的便捷弹窗方法（封装 sheet 弹窗）
    /// - Parameters:
    ///   - selection: 绑定的文件预览数据源（为 nil 时关闭弹窗，有值时弹出）
    ///   - onDismiss: 弹窗关闭时的可选回调
    /// - Returns: 包装后的 View
    func unifiedFilePreview(
        selection: Binding<FilePreviewInput?>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        // 系统弹窗：根据绑定的文件数据自动显示/隐藏
        sheet(item: selection, onDismiss: onDismiss) { input in
            // 展示统一文件预览页面
            UnifiedFilePreview(input: input) {
                // 关闭回调：清空绑定数据，自动收起弹窗
                selection.wrappedValue = nil
            }
        }
    }
}
