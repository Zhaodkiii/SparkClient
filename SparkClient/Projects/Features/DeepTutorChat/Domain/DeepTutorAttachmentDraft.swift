import Foundation
import UniformTypeIdentifiers

enum DeepTutorComposerAttachmentSource: String, Sendable {
    case camera
    case photoLibrary
    case document
}

enum DeepTutorComposerAttachmentKind: String, Equatable, Sendable {
    case image
    case pdf
    case file
}

enum DeepTutorComposerAttachmentPhase: String, Equatable, Sendable {
    case localSelected
    case uploading
    case uploaded
    case failed
}

struct DeepTutorComposerAttachmentDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var source: DeepTutorComposerAttachmentSource
    var kind: DeepTutorComposerAttachmentKind
    var data: Data
    var displayName: String
    var mimeType: String?
    var utTypeIdentifier: String?
    var byteCount: Int
    var localPreviewURL: URL?
    var phase: DeepTutorComposerAttachmentPhase
    var uploadProgress: Double
    var uploaded: DeepTutorUploadedAttachment?
    var errorMessage: String?

    var isBlockingSend: Bool {
        switch phase {
        case .localSelected, .uploading, .failed:
            return true
        case .uploaded:
            return false
        }
    }

    var isImage: Bool { kind == .image }

    var resolvedUTType: UTType? {
        if let utTypeIdentifier, let type = UTType(utTypeIdentifier) {
            return type
        }
        if let mimeType, let type = UTType(mimeType: mimeType) {
            return type
        }
        let ext = (displayName as NSString).pathExtension
        if ext.isEmpty == false {
            return UTType(filenameExtension: ext)
        }
        return nil
    }
}

struct DeepTutorUploadedAttachment: Equatable, Sendable {
    var id: String
    var type: String
    var filename: String
    var mimeType: String?
    var fileId: Int64?
    var fileUuid: String?
    var objectKey: String?
    var remoteURL: URL?
    var fullCacheKey: String?
    var fileMd5: String?
    var localPath: String?
    var originalByteCount: Int
    var aiByteCount: Int?
}

struct DeepTutorOutgoingAttachment: Codable, Equatable, Sendable {
    var id: String
    var type: String
    var filename: String
    var base64: String?
    var url: String?
    var mimeType: String?

    enum CodingKeys: String, CodingKey {
        case id, type, filename, base64, url
        case mimeType = "mime_type"
    }
}

extension DeepTutorUploadedAttachment {
    func outgoingAttachment(aiBase64: String? = nil) -> DeepTutorOutgoingAttachment {
        DeepTutorOutgoingAttachment(
            id: id,
            type: type,
            filename: filename,
            base64: aiBase64,
            url: remoteURL?.absoluteString,
            mimeType: mimeType
        )
    }

    func persistedAttachment() -> DeepTutorAttachment {
        DeepTutorAttachment(
            id: id,
            type: type,
            filename: filename,
            mimeType: mimeType,
            localPath: localPath,
            previewURL: remoteURL?.absoluteString,
            generated: false,
            fileId: fileId,
            fileUuid: fileUuid,
            objectKey: objectKey,
            fullCacheKey: fullCacheKey,
            fileMd5: fileMd5,
            byteCount: originalByteCount,
            aiByteCount: aiByteCount
        )
    }
}
