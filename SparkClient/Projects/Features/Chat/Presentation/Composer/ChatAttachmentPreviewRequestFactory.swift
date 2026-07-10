import Foundation

/// 聊天附件预览路由：图片走公共全屏预览，非图片走 Quick Look。
enum ChatAttachmentPreviewRoute: Identifiable, Equatable {
    struct ImageRequest: Identifiable, Equatable {
        let id: UUID
        let inputs: [FilePreviewInput]
        let selectedID: UUID

        init(id: UUID = UUID(), inputs: [FilePreviewInput], selectedID: UUID) {
            self.id = id
            self.inputs = inputs
            self.selectedID = selectedID
        }
    }

    struct QuickLookRequest: Identifiable, Equatable {
        let id: UUID
        let inputs: [FilePreviewInput]
        let startIndex: Int

        init(id: UUID = UUID(), inputs: [FilePreviewInput], startIndex: Int) {
            self.id = id
            self.inputs = inputs
            self.startIndex = startIndex
        }
    }

    case images(ImageRequest)
    case quickLook(QuickLookRequest)

    var id: UUID {
        switch self {
        case .images(let request):
            return request.id
        case .quickLook(let request):
            return request.id
        }
    }
}

/// 将附件点击转换为预览路由；图片集合按 ID 定位，避免过滤后索引漂移。
enum ChatAttachmentPreviewRequestFactory {
    static func makeRoute(
        inputs: [FilePreviewInput],
        tappedID: UUID
    ) -> ChatAttachmentPreviewRoute? {
        guard let tappedIndex = inputs.firstIndex(where: { $0.id == tappedID }) else {
            return nil
        }
        let tapped = inputs[tappedIndex]
        if tapped.isImage {
            let imageInputs = inputs.filter(\.isImage)
            guard imageInputs.contains(where: { $0.id == tapped.id }) else {
                return nil
            }
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "Chat attachment preview route=images count=\(imageInputs.count)"
            )
            return .images(.init(inputs: imageInputs, selectedID: tapped.id))
        }

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "Chat attachment preview route=quickLook index=\(tappedIndex)"
        )
        return .quickLook(.init(inputs: inputs, startIndex: tappedIndex))
    }

    static func makeRoute(
        attachments: [ChatComposerAttachmentPreview],
        tappedID: UUID
    ) -> ChatAttachmentPreviewRoute? {
        makeRoute(inputs: attachments.map(\.previewInput), tappedID: tappedID)
    }
}
