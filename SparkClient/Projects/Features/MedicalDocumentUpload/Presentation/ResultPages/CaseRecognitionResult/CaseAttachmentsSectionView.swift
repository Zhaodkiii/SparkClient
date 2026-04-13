import SwiftUI

struct CaseAttachmentsSectionView: View {
    let attachments: [CaseLocalAttachmentItem]

    @State private var selectedPreview: FilePreviewInput?

    var body: some View {
        CaseSectionCard(
            title: "附件管理",
            subtitle: "附件列表复用公共预览能力",
            systemImage: "paperclip",
            badgeText: "\(attachments.count)个"
        ) {
            if attachments.isEmpty {
                Text("暂无附件")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(attachments) { item in
                        Button {
                            selectedPreview = item.previewInput
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .unifiedFilePreview(selection: $selectedPreview)
    }

    private func row(_ item: CaseLocalAttachmentItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 40, height: 40)
                Image(systemName: item.symbolName)
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
