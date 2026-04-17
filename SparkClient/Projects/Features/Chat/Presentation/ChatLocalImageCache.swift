import Foundation
import UIKit

/// 与 `FileCacheManager` 使用相同的缓存目录与文件名规则，供聊天 UI 同步解析本地缩略图（避免重复引入 actor 依赖）。
enum ChatLocalImageCache {
    private static func sanitizedFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let components = raw.components(separatedBy: invalid)
        let collapsed = components.joined(separator: "_")
        return collapsed.isEmpty ? "unnamed_file" : collapsed
    }

    /// 若上传后的文件仍缓存在 `Library/Caches/SparkClient.FileCache/<uuid>/` 下，则返回 `UIImage`。
    static func uiImageIfCached(fileUUID: String, originalName: String) -> UIImage? {
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let base = caches
            .appendingPathComponent("SparkClient.FileCache", isDirectory: true)
            .appendingPathComponent(fileUUID.lowercased(), isDirectory: true)
        let url = base.appendingPathComponent(sanitizedFileName(originalName))
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
