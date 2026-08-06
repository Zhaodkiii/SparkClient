import SwiftUI

struct DeepTutorContextReferenceTreeView: View {
    let attachments: [DeepTutorAttachment]
    let references: [DeepTutorContextReference]
    @State private var isExpanded = false

    private var items: [ReferenceItem] {
        let attachmentItems = attachments.map {
            ReferenceItem(id: $0.id, title: $0.filename ?? $0.type, subtitle: $0.mimeType, icon: "paperclip")
        }
        let referenceItems = references.map {
            ReferenceItem(id: $0.id, title: $0.title, subtitle: $0.subtitle, icon: "link")
        }
        return attachmentItems + referenceItems
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else if items.count == 1, let item = items.first {
            referenceRow(item)
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                Button(isExpanded ? "Hide references" : "Show \(items.count) references") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                if isExpanded {
                    ForEach(items) { item in
                        referenceRow(item)
                    }
                }
            }
        }
    }

    private func referenceRow(_ item: ReferenceItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private struct ReferenceItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let icon: String
    }
}
