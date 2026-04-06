import Foundation

enum ChatComposerAttachmentSource: String, Sendable {
    case photoLibrary
    case camera
    case document
}

struct ChatComposerAttachmentPreview: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: ChatComposerAttachmentSource
    let imageData: Data
    let displayName: String

    init(
        id: UUID = UUID(),
        source: ChatComposerAttachmentSource,
        imageData: Data,
        displayName: String
    ) {
        self.id = id
        self.source = source
        self.imageData = imageData
        self.displayName = displayName
    }
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
