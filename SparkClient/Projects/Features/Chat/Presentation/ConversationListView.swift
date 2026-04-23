import SwiftUI

//struct ConversationListView: View {
//    let items: [ChatThreadListItem]
//    let selectedThreadID: UUID?
//    let onSelect: (UUID) -> Void
//    let onCreate: () -> Void
//    let onDelete: (UUID) -> Void
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            HStack {
//                Text(L10n.text("chat.title"))
//                    .font(.headline)
//                Spacer()
//                Button(action: onCreate) {
//                    Image(systemName: "plus.bubble")
//                }
//                .buttonStyle(.borderless)
//            }
//            .padding(.horizontal, 12)
//
//            ScrollView(.horizontal, showsIndicators: false) {
//                HStack(spacing: 10) {
//                    ForEach(items) { item in
//                        Button {
//                            onSelect(item.id)
//                        } label: {
//                            VStack(alignment: .leading, spacing: 4) {
//                                Text(item.thread.listDisplayTitle)
//                                    .font(.subheadline.weight(.semibold))
//                                    .lineLimit(1)
//                                Text(item.latestMessagePreview)
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                                    .lineLimit(1)
//                            }
//                            .padding(.horizontal, 10)
//                            .padding(.vertical, 8)
//                            .frame(width: 180, alignment: .leading)
//                            .background(
//                                RoundedRectangle(cornerRadius: 10)
//                                    .fill(item.id == selectedThreadID ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground))
//                            )
//                        }
//                        .buttonStyle(.plain)
//                        .contextMenu {
//                            Button(role: .destructive) {
//                                onDelete(item.id)
//                            } label: {
//                                Label(L10n.text("common.delete"), systemImage: "trash")
//                            }
//                        }
//                    }
//                }
//                .padding(.horizontal, 12)
//            }
//        }
//        .padding(.vertical, 6)
//        .background(Color(uiColor: .systemGroupedBackground))
//    }
//}
