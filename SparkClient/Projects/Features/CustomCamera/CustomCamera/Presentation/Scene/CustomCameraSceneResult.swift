/// 自定义相机拍摄完成后的统一结果模型。

import Foundation
import AVFoundation
import UIKit
import AVFoundation

struct CustomCameraSceneResult: Sendable, Equatable {
    enum MediaType: Sendable, Equatable {
        case photo
        case video
    }

    let mediaType: MediaType
    let localURL: URL?
    let image: UIImage?
    let createdAt: Date
    let source: String

    init(media: CustomCameraMedia, createdAt: Date = Date(), source: String = "custom_camera") {
        if let image = media.getImage() {
            self.mediaType = .photo
            self.image = image
            self.localURL = nil
        } else if let video = media.getVideo() {
            self.mediaType = .video
            self.image = nil
            self.localURL = video
        } else {
            self.mediaType = .photo
            self.image = nil
            self.localURL = nil
        }
        self.createdAt = createdAt
        self.source = source
    }
}
