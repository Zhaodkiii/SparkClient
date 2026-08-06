import Foundation
import UniformTypeIdentifiers

enum DeepTutorAttachmentMapper {
    static let maxComposerAttachments = 6

    static func makeDrafts(from files: [MedicalUploadLocalFile]) async -> [DeepTutorComposerAttachmentDraft] {
        var drafts: [DeepTutorComposerAttachmentDraft] = []

        for file in files {
            guard let data = try? Data(contentsOf: file.url), data.isEmpty == false else {
                continue
            }

            let inferred = UTType(filenameExtension: file.url.pathExtension)
                ?? file.mimeType.flatMap { UTType(mimeType: $0) }
            let kind: DeepTutorComposerAttachmentKind
            if inferred?.conforms(to: .pdf) == true {
                kind = .pdf
            } else if inferred?.conforms(to: .image) == true {
                kind = .image
            } else {
                kind = .file
            }

            drafts.append(
                DeepTutorComposerAttachmentDraft(
                    id: file.id,
                    source: .document,
                    kind: kind,
                    data: data,
                    displayName: file.displayName,
                    mimeType: file.mimeType ?? inferred?.preferredMIMEType,
                    utTypeIdentifier: inferred?.identifier,
                    byteCount: data.count,
                    localPreviewURL: file.url,
                    phase: .localSelected,
                    uploadProgress: 0,
                    uploaded: nil,
                    errorMessage: nil
                )
            )
        }

        return drafts
    }
}

enum DeepTutorSendAttachmentAssembly {
    nonisolated static let businessType = "deep_tutor_attachment"

    nonisolated static func makeUploadedAttachment(
        draft: DeepTutorComposerAttachmentDraft,
        record: ManagedFileRecord,
        publicFullURL: URL?
    ) -> DeepTutorUploadedAttachment {
        let attachmentType: String = switch draft.kind {
        case .image: "image"
        case .pdf: "pdf"
        case .file: "file"
        }
        return DeepTutorUploadedAttachment(
            id: draft.id.uuidString,
            type: attachmentType,
            filename: record.originalName,
            mimeType: record.mimeType,
            fileId: Int64(record.id),
            fileUuid: record.fileUuid,
            objectKey: record.objectKey,
            remoteURL: publicFullURL,
            fullCacheKey: ChatAttachment.makeFullCacheKey(fileUUID: record.fileUuid, fileName: record.originalName),
            fileMd5: record.fileMd5,
            localPath: draft.localPreviewURL?.path,
            originalByteCount: draft.byteCount,
            aiByteCount: nil
        )
    }
}

struct DeepTutorAttachmentUploadUseCase: Sendable {
    let fileTransferService: FileTransferService

    func upload(
        draft: DeepTutorComposerAttachmentDraft,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> DeepTutorUploadedAttachment {
        let record = try await fileTransferService.upload(
            ManagedFileUploadPayload(
                data: draft.data,
                fileName: draft.displayName,
                businessType: DeepTutorSendAttachmentAssembly.businessType,
                businessId: draft.id.uuidString,
                isPublic: false,
                onUploadProgress: onProgress
            )
        )
        let publicURL = await fileTransferService.publicHTTPSURLForObjectKey(record.objectKey)
        return DeepTutorSendAttachmentAssembly.makeUploadedAttachment(
            draft: draft,
            record: record,
            publicFullURL: publicURL
        )
    }
}

enum DeepTutorAttachmentSendTextBuilder {
    static func effectiveSendText(
        userText: String,
        attachments: [DeepTutorAttachment]
    ) -> String {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }
        let hasImage = attachments.contains { $0.type == "image" }
        let hasFile = attachments.contains { $0.type == "pdf" || $0.type == "file" }
        if hasImage {
            return "请分析附件图片。"
        }
        if hasFile {
            return "请阅读附件并回答。"
        }
        return trimmed
    }
}

enum DeepTutorAttachmentPreviewInputBuilder {
    static func previewInput(for draft: DeepTutorComposerAttachmentDraft) -> FilePreviewInput {
        if let localPreviewURL = draft.localPreviewURL,
           FileManager.default.fileExists(atPath: localPreviewURL.path) {
            return FilePreviewInput(
                id: draft.id,
                fileURL: localPreviewURL,
                displayName: draft.displayName,
                mimeType: draft.mimeType,
                utTypeIdentifier: draft.utTypeIdentifier
            )
        }

        let ext = (draft.displayName as NSString).pathExtension
        let suffix = ext.isEmpty ? (draft.isImage ? "jpg" : "bin") : ext
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("deeptutor-composer-\(draft.id.uuidString).\(suffix)")
        do {
            try draft.data.write(to: tmp, options: [.atomic])
            return FilePreviewInput(
                id: draft.id,
                fileURL: tmp,
                displayName: draft.displayName,
                mimeType: draft.mimeType,
                utTypeIdentifier: draft.utTypeIdentifier
            )
        } catch {
            return FilePreviewInput(
                id: draft.id,
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("deeptutor-attachment-missing-\(draft.id.uuidString)"),
                displayName: draft.displayName,
                mimeType: draft.mimeType,
                utTypeIdentifier: draft.utTypeIdentifier
            )
        }
    }

    static func previewInputs(for drafts: [DeepTutorComposerAttachmentDraft]) -> [FilePreviewInput] {
        drafts.map(previewInput(for:))
    }
}
