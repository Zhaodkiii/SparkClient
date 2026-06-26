import Foundation
import UIKit

/// Shared JPEG compression for AI multimodal requests (chat, medical vision extraction, nutrition, etc.).
struct AIImageCompressor: Sendable {
    nonisolated static let defaultTargetByteCount = 1_048_576

    nonisolated static func compressForAI(
        imageData: Data,
        targetByteCount: Int = defaultTargetByteCount
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }

        let maxDimensions: [CGFloat] = [2048, 1600, 1280, 1024, 768]
        let qualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.45]
        var smallestCandidate: Data?

        for maxDimension in maxDimensions {
            let resized = resizedImage(image, maxDimension: maxDimension)
            for quality in qualities {
                guard let data = resized.jpegData(compressionQuality: quality) else { continue }
                if smallestCandidate == nil || data.count < (smallestCandidate?.count ?? Int.max) {
                    smallestCandidate = data
                }
                if data.count <= targetByteCount {
                    return data
                }
            }
        }

        return smallestCandidate
    }

    private nonisolated static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return image }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
