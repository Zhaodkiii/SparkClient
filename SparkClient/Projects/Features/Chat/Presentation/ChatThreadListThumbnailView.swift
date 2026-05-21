import SwiftUI
import UIKit

/// 会话列表缩略图：对齐医疗附件网格「先本地缓存、再按需下载」；行级 `.task` 懒加载。
struct ChatThreadListThumbnailView: View {
    let attachment: ChatAttachment
    let fileTransferService: FileTransferService

    @State private var inlineImage: UIImage?
    @State private var localURL: URL?
    @State private var isDownloading = false
    @State private var loadFailed = false

    private let side: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))

            if isDownloading {
                ProgressView()
                    .controlSize(.regular)
            } else if let inlineImage {
                Image(uiImage: inlineImage)
                    .resizable()
                    .scaledToFill()
            } else if let localURL {
                LocalFileImageThumbnail(url: localURL)
                    .frame(width: side, height: side)
                    .clipped()
            } else if loadFailed {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: attachment.imageDownloadDedupeKey) {
            await loadThumbnailIfNeeded()
        }
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        ChatAttachmentImageDiagnostics.debug(
            "listThumb.start id=\(attachment.id.uuidString.prefix(8))"
        )
        inlineImage = nil
        localURL = nil
        isDownloading = false
        loadFailed = false

        if let image = ChatAttachment.inlinePreviewUIImage(from: attachment) {
            inlineImage = image
            return
        }

        if let parsed = attachment.sparkClientOSSFileUUIDAndFileName(),
           let cachedURL = ChatLocalImageCache.cachedFileURLIfPresent(
               fileUUID: parsed.fileUUID,
               originalName: parsed.fileName
           ) {
            localURL = cachedURL
            ChatAttachmentImageDiagnostics.info(
                "listThumb.localCacheHit attachmentID=\(attachment.id.uuidString.prefix(8))"
            )
            return
        }

        guard let managedFile = attachment.managedFileRecordForDownload() else {
            loadFailed = true
            ChatAttachmentImageDiagnostics.warning("listThumb.abort missing url")
            return
        }

        if let cachedURL = await fileTransferService.cachedURL(file: managedFile) {
            localURL = cachedURL
            return
        }

        isDownloading = true
        defer { isDownloading = false }

        do {
            let downloaded = try await fileTransferService.download(file: managedFile)
            localURL = downloaded
            ChatAttachmentImageDiagnostics.info(
                "listThumb.downloadOK attachmentID=\(attachment.id.uuidString.prefix(8))"
            )
        } catch {
            loadFailed = true
            ChatAttachmentImageDiagnostics.warning(
                "listThumb.downloadFail error=\(ChatAttachmentImageDiagnostics.errorDescription(error))"
            )
        }
    }
}
