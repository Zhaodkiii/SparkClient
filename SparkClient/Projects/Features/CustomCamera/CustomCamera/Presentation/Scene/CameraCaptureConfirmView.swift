//
//  CameraCaptureConfirmView.swift
//
//  通用「拍摄结果确认」页面：使用项目统一的 QuickLook 预览展示照片，
//  左上角取消（重新拍摄），右上角确认（完成拍摄）。
//

import SwiftUI

/// 待确认的拍摄结果：同时持有原始图片与用于 QuickLook 预览的本地文件。
struct CameraCapturePending: Identifiable {
    let id = UUID()
    let image: UIImage
    let previewInput: FilePreviewInput
}

extension CameraCapturePending {
    /// 把拍摄到的图片写入临时文件，构造可供 QuickLook 预览的待确认对象。
    static func make(from image: UIImage, displayName: String = "拍摄结果") -> CameraCapturePending? {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera_capture_\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }

        let input = FilePreviewInput(fileURL: url, displayName: displayName)
        return CameraCapturePending(image: image, previewInput: input)
    }

    /// 移除临时预览文件。
    func cleanup() {
        try? FileManager.default.removeItem(at: previewInput.fileURL)
    }
}

/// 拍摄结果确认页面（通用，可被任意相机场景复用）。
struct CameraCaptureConfirmView: View {
    let pending: CameraCapturePending
    /// 取消：返回重新拍摄。
    let onCancel: () -> Void
    /// 确认：完成拍摄。
    let onConfirm: () -> Void

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            QuickLookPreviewBridge(inputs: [pending.previewInput], startIndex: 0)
                .ignoresSafeArea()
                .navigationTitle("确认照片")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消", action: onCancel)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: onConfirm) {
                            Text("确认").fontWeight(.semibold)
                        }
                    }
                }
        }
    }
}
