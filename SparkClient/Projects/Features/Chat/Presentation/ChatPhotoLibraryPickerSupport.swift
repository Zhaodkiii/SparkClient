import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// 相册多选结果：保留原始文件名（来自 `loadFileRepresentation` 临时 URL 的 `lastPathComponent`）。
struct ChatComposerPickedPhoto: Sendable {
    let imageData: Data
    let suggestedFileName: String
}

enum ChatComposerPhotoLibraryLoader {
    static func load(from results: [PHPickerResult], completion: @escaping ([ChatComposerPickedPhoto]) -> Void) {
        guard results.isEmpty == false else {
            completion([])
            return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var picked: [ChatComposerPickedPhoto] = []

        for result in results {
            group.enter()
            loadOne(result: result) { photo in
                defer { group.leave() }
                guard let photo else { return }
                lock.lock()
                picked.append(photo)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            completion(picked)
        }
    }

    private static func loadOne(result: PHPickerResult, completion: @escaping (ChatComposerPickedPhoto?) -> Void) {
        let provider = result.itemProvider
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            completion(nil)
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
            if let url, let data = try? Data(contentsOf: url), data.isEmpty == false {
                let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                let safe = name.isEmpty ? "image.jpg" : name
                completion(ChatComposerPickedPhoto(imageData: data, suggestedFileName: safe))
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage,
                      let jpeg = image.jpegData(compressionQuality: 0.88) ?? image.pngData() else {
                    completion(nil)
                    return
                }
                completion(ChatComposerPickedPhoto(imageData: jpeg, suggestedFileName: "photo.jpg"))
            }
        }
    }
}
