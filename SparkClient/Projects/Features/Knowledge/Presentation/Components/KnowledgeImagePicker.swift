import SwiftUI
import UIKit

/// 供知识 OCR 使用：`UIImagePickerController` 封装（与 `ChatCameraPicker` 同构，支持相机与相册）。
struct KnowledgeImagePicker: UIViewControllerRepresentable {
    enum Source {
        case camera
        case photoLibrary
    }

    let source: Source
    let onCancel: () -> Void
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        switch source {
        case .camera:
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        case .photoLibrary:
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: KnowledgeImagePicker

        init(_ parent: KnowledgeImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            } else {
                parent.onCancel()
            }
        }
    }
}
