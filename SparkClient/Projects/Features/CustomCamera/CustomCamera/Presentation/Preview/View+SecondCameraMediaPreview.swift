import SwiftUI

extension View {
    /// 公共相机风格图片全屏预览（`fullScreenCover`）。第一阶段仅支持只读模式。
    func secondCameraMediaPreview(
        isPresented: Binding<Bool>,
        inputs: [FilePreviewInput],
        startIndex: Int = 0,
        mode: SecondCameraMediaPreviewMode = .readOnly,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            SecondCameraPublicMediaPreview(
                inputs: inputs,
                startIndex: startIndex,
                mode: mode,
                onClose: { isPresented.wrappedValue = false }
            )
        }
    }

    /// 以选中附件 ID 打开公共只读图片全屏预览。
    func secondCameraMediaPreview(
        item: Binding<SecondCameraPublicMediaPreviewRequest?>
    ) -> some View {
        fullScreenCover(item: item) { request in
            SecondCameraPublicMediaPreview(
                inputs: request.inputs,
                selectedID: request.selectedID,
                mode: .readOnly,
                onClose: { item.wrappedValue = nil }
            )
        }
    }
}

/// `fullScreenCover(item:)` 用的稳定请求模型。
struct SecondCameraPublicMediaPreviewRequest: Identifiable, Equatable {
    let id: UUID
    let inputs: [FilePreviewInput]
    let selectedID: UUID

    init(id: UUID = UUID(), inputs: [FilePreviewInput], selectedID: UUID) {
        self.id = id
        self.inputs = inputs
        self.selectedID = selectedID
    }
}
