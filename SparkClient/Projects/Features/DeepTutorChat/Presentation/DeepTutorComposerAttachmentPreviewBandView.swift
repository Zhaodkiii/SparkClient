import SwiftUI

struct DeepTutorComposerAttachmentPreviewBandView: View {
    let drafts: [DeepTutorComposerAttachmentDraft]
    let onUpload: (UUID) -> Void
    let onRetry: (UUID) -> Void
    let onRemove: (UUID) -> Void
    let onPreview: (UUID) -> Void

    var body: some View {
        if drafts.isEmpty == false {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(drafts) { draft in
                            DeepTutorComposerAttachmentThumbnailView(
                                draft: draft,
                                onUpload: { onUpload(draft.id) },
                                onRetry: { onRetry(draft.id) },
                                onRemove: { onRemove(draft.id) },
                                onPreview: { onPreview(draft.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                Rectangle()
                    .fill(DeepTutorPalette.mutedBorderColor)
                    .frame(height: 1)
            }
            .background(DeepTutorPalette.mutedSurface)
        }
    }
}
