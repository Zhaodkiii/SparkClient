import SwiftUI

struct MedicalDocumentPreviewGrid: View {
    let items: [FilePreviewInput]
    let onTap: (Int) -> Void
    let onRemove: (UUID) -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        onTap(index)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: item.isImage ? "photo" : "doc.richtext")
                                .font(.title2)
                            Text(item.resolvedDisplayName)
                                .font(.footnote)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        onRemove(item.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
    }
}
