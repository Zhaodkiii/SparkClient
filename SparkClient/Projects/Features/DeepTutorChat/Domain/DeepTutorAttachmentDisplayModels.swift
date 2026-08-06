import Foundation
import UIKit

struct DeepTutorImageAttachmentPayload: Identifiable, Equatable {
    let id: UUID
    let url: URL?
    let localURL: URL?
    let displayName: String
    let mimeType: String?
    let fullCacheKey: String?
    let managedFile: ManagedFileRecord?
}

enum DeepTutorAttachmentDisplayBuilder {
    static func imagePayloads(from attachments: [DeepTutorAttachment]) -> [DeepTutorImageAttachmentPayload] {
        attachments.compactMap { attachment in
            guard attachment.type == "image" else { return nil }
            let stableID = UUID(uuidString: attachment.id) ?? UUID(uuidString: attachment.id.lowercased()) ?? UUID()
            let downloadURL = attachment.resolvedRemoteURL
            let localURL = attachment.localPath.map(URL.init(fileURLWithPath:))
            let managedFile = attachment.managedFileRecord(downloadURL: downloadURL)

            if let localURL,
               let image = UIImage(contentsOfFile: localURL.path) {
                return DeepTutorImageAttachmentPayload(
                    id: stableID,
                    url: nil,
                    localURL: localURL,
                    displayName: attachment.filename ?? "image.jpg",
                    mimeType: attachment.mimeType,
                    fullCacheKey: attachment.fullCacheKey,
                    managedFile: nil
                )
            }

            if let parsed = attachment.sparkClientOSSFileUUIDAndFileName(),
               let cached = ChatLocalImageCache.uiImageIfCached(fileUUID: parsed.fileUUID, originalName: parsed.fileName) {
                _ = cached
                return DeepTutorImageAttachmentPayload(
                    id: stableID,
                    url: downloadURL,
                    localURL: nil,
                    displayName: attachment.filename ?? "image.jpg",
                    mimeType: attachment.mimeType,
                    fullCacheKey: attachment.fullCacheKey,
                    managedFile: managedFile
                )
            }

            return DeepTutorImageAttachmentPayload(
                id: stableID,
                url: downloadURL,
                localURL: localURL,
                displayName: attachment.filename ?? "image.jpg",
                mimeType: attachment.mimeType,
                fullCacheKey: attachment.fullCacheKey,
                managedFile: managedFile
            )
        }
    }

    static func fileAttachments(from attachments: [DeepTutorAttachment]) -> [DeepTutorAttachment] {
        attachments.filter { $0.type == "pdf" || $0.type == "file" }
    }
}
