import Foundation

enum DeepTutorAttachmentDiagnostics {
    private static var lastLoggedProgress: [UUID: Int] = [:]
    private static let progressLock = NSLock()

    static func pickStart(source: String) {
        DeepTutorChatLog.attachmentPickStart(source: source)
    }

    static func pickDone(_ drafts: [DeepTutorComposerAttachmentDraft]) {
        let imageCount = drafts.filter { $0.kind == .image }.count
        let pdfCount = drafts.filter { $0.kind == .pdf }.count
        let totalBytes = drafts.reduce(0) { $0 + $1.byteCount }
        DeepTutorChatLog.attachmentPickDone(
            count: drafts.count,
            imageCount: imageCount,
            pdfCount: pdfCount,
            totalBytes: totalBytes
        )
        for draft in drafts {
            DeepTutorChatLog.attachmentPreviewAdded(
                draftID: draft.id,
                kind: draft.kind.rawValue,
                filename: draft.displayName,
                bytes: draft.byteCount
            )
        }
    }

    static func uploadStart(draftID: UUID, filename: String) {
        DeepTutorChatLog.attachmentUploadStart(draftID: draftID, filename: filename)
    }

    static func uploadProgress(draftID: UUID, progress: Double) {
        let bucket = Int((progress * 10).rounded(.down) * 10)
        progressLock.lock()
        let previous = lastLoggedProgress[draftID] ?? -1
        guard bucket > previous else {
            progressLock.unlock()
            return
        }
        lastLoggedProgress[draftID] = bucket
        progressLock.unlock()
        DeepTutorChatLog.attachmentUploadProgress(draftID: draftID, progress: progress)
    }

    static func uploadDone(draftID: UUID, uploaded: DeepTutorUploadedAttachment, durationMs: Int) {
        progressLock.lock()
        lastLoggedProgress.removeValue(forKey: draftID)
        progressLock.unlock()
        DeepTutorChatLog.attachmentUploadDone(
            draftID: draftID,
            attachmentID: uploaded.id,
            url: uploaded.remoteURL?.absoluteString,
            durationMs: durationMs
        )
    }

    static func uploadFailed(draftID: UUID, error: String) {
        progressLock.lock()
        lastLoggedProgress.removeValue(forKey: draftID)
        progressLock.unlock()
        DeepTutorChatLog.attachmentUploadFailed(draftID: draftID, error: error)
    }

    static func sendBuild(count: Int, imageCount: Int, fileCount: Int, hasText: Bool) {
        DeepTutorChatLog.attachmentSendBuild(
            count: count,
            imageCount: imageCount,
            fileCount: fileCount,
            hasText: hasText
        )
    }

    static func snapshotSaved(messageID: UUID, attachmentCount: Int) {
        DeepTutorChatLog.attachmentSnapshotSaved(messageID: messageID, attachmentCount: attachmentCount)
    }
}
