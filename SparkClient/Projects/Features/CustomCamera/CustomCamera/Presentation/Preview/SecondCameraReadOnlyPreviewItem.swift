import Foundation
import UniformTypeIdentifiers
import UIKit

/// 公共只读预览队列中的单条输入快照项。
struct SecondCameraReadOnlyPreviewItem: Identifiable {
    let id: UUID
    let fileURL: URL
    let displayName: String
    let inferredUTType: UTType?

    var thumbnail: UIImage?
    var image: UIImage?
    var revision: Int = 0
    var loadState: LoadState = .idle

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(SecondCameraMediaPreviewLoadError)
    }

    var displayItem: SecondCameraMediaPreviewDisplayItem {
        let content: SecondCameraMediaPreviewDisplayItem.Content
        switch loadState {
        case .idle:
            content = .idle
        case .loading:
            if let image {
                content = .image(image)
            } else {
                content = .loading
            }
        case .loaded:
            if let image {
                content = .image(image)
            } else {
                content = .failure(.cannotDecodeImage)
            }
        case .failed(let error):
            content = .failure(error)
        }

        return SecondCameraMediaPreviewDisplayItem(
            id: id,
            title: displayName,
            revision: revision,
            thumbnail: thumbnail,
            content: content
        )
    }
}
