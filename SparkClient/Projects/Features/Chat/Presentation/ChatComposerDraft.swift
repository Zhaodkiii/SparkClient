import Foundation
import UniformTypeIdentifiers

enum ChatComposerAttachmentSource: String, Sendable {
    case photoLibrary
    case camera
    case document
}

enum ChatComposerAttachmentKind: String, Equatable, Sendable {
    case image
    case pdf
    case file
}

struct ChatComposerAttachmentPreview: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: ChatComposerAttachmentSource
    let kind: ChatComposerAttachmentKind
    let data: Data
    let displayName: String
    let mimeType: String?
    let utTypeIdentifier: String?

    init(
        id: UUID = UUID(),
        source: ChatComposerAttachmentSource,
        kind: ChatComposerAttachmentKind = .image,
        data: Data,
        displayName: String,
        mimeType: String? = nil,
        utTypeIdentifier: String? = nil
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.data = data
        self.displayName = displayName
        self.mimeType = mimeType
        self.utTypeIdentifier = utTypeIdentifier
    }

    var isImage: Bool {
        kind == .image
    }

    var isPDF: Bool {
        kind == .pdf
    }

    var resolvedUTType: UTType? {
        if let utTypeIdentifier,
           let type = UTType(utTypeIdentifier) {
            return type
        }
        if let mimeType,
           let type = UTType(mimeType: mimeType) {
            return type
        }
        let ext = (displayName as NSString).pathExtension
        if ext.isEmpty == false {
            return UTType(filenameExtension: ext)
        }
        return nil
    }
}

enum ChatComposerAttachmentPhase: String, Equatable, Sendable {
    case pending
    case uploading
    case ocring
    case success
    case failed
}

struct ChatComposerPreparedAttachmentState: Equatable, Sendable {
    var phase: ChatComposerAttachmentPhase
    var progress: Double
    var prepared: ChatPreparedAttachment?
    var errorMessage: String?

    static let pending = ChatComposerPreparedAttachmentState(
        phase: .pending,
        progress: 0,
        prepared: nil,
        errorMessage: nil
    )
}

struct ChatComposerDraft: Equatable, Sendable {
    var text: String = ""
    var attachments: [ChatComposerAttachmentPreview] = []
    var runtimeFlags: ChatComposerRuntimeFlags = ChatComposerRuntimeFlags()
    var isShowingAttachmentMenu = false
    var isShowingPhotoPicker = false
    var isShowingCamera = false
    var previewSelection: UUID?

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasVisualContent: Bool {
        trimmedText.isEmpty == false || attachments.isEmpty == false
    }
}
