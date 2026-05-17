import SwiftUI

struct CaseMatchedAttachmentsGridView: View {
    let title: String?
    let attachments: [CaseLocalAttachmentItem]

    @State private var selectedPreview: FilePreviewInput?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        if attachments.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                if let title, title.isEmpty == false {
                    Label(title, systemImage: "paperclip")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(attachments) { item in
                        Button {
                            selectedPreview = item.previewInput
                        } label: {
                            gridCard(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .unifiedFilePreview(selection: $selectedPreview)
        }
    }

    private func gridCard(_ item: CaseLocalAttachmentItem) -> some View {
        GeometryReader { geometry in
            let cardSize = geometry.size.width

            ZStack(alignment: .bottomLeading) {
                if item.previewInput.isImage {
                    LocalFileImageThumbnail(url: item.fileURL)
                        .frame(width: cardSize, height: cardSize)
                        .clipped()
                        .background(Color(uiColor: .tertiarySystemFill))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: min(cardSize * 0.3, 30)))
                            .foregroundStyle(item.tintColor)
                        Text(item.displayName)
                            .font(.system(size: min(cardSize * 0.11, 11)))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: cardSize, height: cardSize)
                    .background(
                        LinearGradient(
                            colors: [
                                item.tintColor.opacity(0.10),
                                Color(uiColor: .systemIndigo).opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }

                Text(item.displayName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.42))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
