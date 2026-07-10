import Foundation
import UIKit

/// 公共 Viewport 的无业务渲染模型。不持有 Store，仅描述当前选中项的显示状态。
struct SecondCameraMediaPreviewDisplayItem: Identifiable {
    let id: UUID
    let title: String?
    let revision: Int
    let thumbnail: UIImage?
    let content: Content

    enum Content {
        case idle
        case loading
        case image(UIImage)
        case video(URL)
        case failure(SecondCameraMediaPreviewLoadError)
    }

    /// SwiftUI / UIKit bridge 用的稳定预览身份：切换项或同项刷新时变化。
    var imageIdentity: String {
        "\(id.uuidString)-\(revision)"
    }
}
