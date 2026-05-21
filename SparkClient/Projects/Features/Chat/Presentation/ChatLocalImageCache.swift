import Foundation
import UIKit

/// 与 `FileCacheManager` 使用相同的缓存目录与文件名规则，供聊天 UI 同步解析本地缩略图（避免重复引入 actor 依赖）。
/// `FileCacheManager` 实际写路径为：`SparkClient.FileCache/{accountNamespace}/{fileUUID}/{fileName}`，
/// 此处通过枚举 namespace 子目录来自动适配，无需持有 actor 引用。
enum ChatLocalImageCache {
    private static func sanitizedFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let components = raw.components(separatedBy: invalid)
        let collapsed = components.joined(separator: "_")
        return collapsed.isEmpty ? "unnamed_file" : collapsed
    }

    /// 若上传后的文件仍缓存在 `Library/Caches/SparkClient.FileCache/{namespace}/{uuid}/` 下，则返回 `UIImage`。
    /// 自动枚举 `accountNamespace` 目录（`guest` / `account-*`），对齐 `FileCacheManager.directoryURL(for:)`。
    static func uiImageIfCached(fileUUID: String, originalName: String) -> UIImage? {
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let base = caches.appendingPathComponent("SparkClient.FileCache", isDirectory: true)
        let sanitized = sanitizedFileName(originalName)
        let lowercasedUUID = fileUUID.lowercased()

        // 枚举 accountNamespace 子目录（guest / account-*），与 FileCacheManager 对齐
        let namespaceDirs = (try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        for nsDir in namespaceDirs {
            guard (try? nsDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let candidate = nsDir
                .appendingPathComponent(lowercasedUUID, isDirectory: true)
                .appendingPathComponent(sanitized)
            if fileManager.fileExists(atPath: candidate.path),
               let data = try? Data(contentsOf: candidate),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    /// 返回已缓存文件的本地 URL（供画廊写入 `downloadedImageFiles` 展示缩略图）。
    static func cachedFileURLIfPresent(fileUUID: String, originalName: String) -> URL? {
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let base = caches.appendingPathComponent("SparkClient.FileCache", isDirectory: true)
        let sanitized = sanitizedFileName(originalName)
        let lowercasedUUID = fileUUID.lowercased()

        let namespaceDirs = (try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        for nsDir in namespaceDirs {
            guard (try? nsDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let candidate = nsDir
                .appendingPathComponent(lowercasedUUID, isDirectory: true)
                .appendingPathComponent(sanitized)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
