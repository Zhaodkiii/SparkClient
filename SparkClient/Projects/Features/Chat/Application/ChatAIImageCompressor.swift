import Foundation

/// Chat feature alias for shared Core compression used by multimodal AI requests.
enum ChatAIImageCompressor {
    nonisolated static let defaultTargetByteCount = AIImageCompressor.defaultTargetByteCount

    nonisolated static func compressForAI(
        imageData: Data,
        targetByteCount: Int = AIImageCompressor.defaultTargetByteCount
    ) -> Data? {
        AIImageCompressor.compressForAI(imageData: imageData, targetByteCount: targetByteCount)
    }
}
