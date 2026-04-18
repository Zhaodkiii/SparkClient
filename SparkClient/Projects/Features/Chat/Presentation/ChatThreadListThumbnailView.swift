import SwiftUI
import UIKit

/// 会话列表缩略图：优先本地缓存，否则懒加载走与详情一致的公共下载。
struct ChatThreadListThumbnailView: View {
    let attachment: ChatAttachment
    let onDownload: (ChatAttachment) async throws -> URL

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: attachment.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        await MainActor.run {
            loadFailed = false
        }
        if let parsed = attachment.sparkClientOSSFileUUIDAndFileName(),
           let cached = ChatLocalImageCache.uiImageIfCached(fileUUID: parsed.fileUUID, originalName: parsed.fileName) {
            await MainActor.run { image = cached }
            return
        }
        guard attachment.effectiveHTTPSImageDownloadURL != nil else {
            await MainActor.run { loadFailed = true }
            return
        }
        do {
            let localURL = try await onDownload(attachment)
            let loaded = UIImage(contentsOfFile: localURL.path)
            await MainActor.run {
                image = loaded
                loadFailed = loaded == nil
            }
        } catch {
            await MainActor.run {
                loadFailed = true
            }
        }
    }
}
