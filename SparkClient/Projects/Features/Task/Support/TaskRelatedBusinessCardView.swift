import SwiftUI

struct TaskRelatedBusinessCardView: View {
    enum ContentState {
        case loading
        case knowledge(document: KnowledgeDocument)
        case unavailable(message: String)
        case unsupported
    }

    let businessTypeName: String
    let businessID: String
    let taskDescription: String
    let contentState: ContentState
    let onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("task.related.section", comment: "关联业务"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            cardBody
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        switch contentState {
        case .knowledge(let document):
            Button(action: { onOpen?() }) {
                knowledgeCard(document: document)
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)

        case .loading:
            shell {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        cardHeader
                        Text(NSLocalizedString("task.related.loading", comment: "正在加载关联内容"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

        case .unavailable(let message):
            shell {
                VStack(alignment: .leading, spacing: 8) {
                    cardHeader
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    if taskDescription.isEmpty == false {
                        Text(taskDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }

        case .unsupported:
            shell {
                VStack(alignment: .leading, spacing: 8) {
                    cardHeader
                    Text(NSLocalizedString("task.related.unsupported", comment: "该业务类型暂不支持预览"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    private func knowledgeCard(document: KnowledgeDocument) -> some View {
        shell {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        cardHeader
                        Text(NSLocalizedString("task.business_type.knowledge", comment: "知识库"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }

                    Text(document.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(document.listSubtitle.isEmpty ? taskDescription : document.listSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var cardHeader: some View {
        Label(businessTypeName, systemImage: "link")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.08), lineWidth: 1)
            )
    }
}

extension String {
    var taskBusinessTypeDisplayName: String {
        switch trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "knowledge":
            return NSLocalizedString("task.business_type.knowledge", comment: "知识库")
        case "":
            return NSLocalizedString("task.business_type.none", comment: "未关联业务")
        default:
            return self
        }
    }
}
