import SwiftUI

/// 会话内的线上问诊消息卡片：样式对齐「最近问诊」列表卡片，附件复用消息内画廊 / 文件块。
struct ConsultationMessageCardView: View {
    let payload: ChatConsultationCardPayload
    let fileTransferService: FileTransferService
    let onTap: () -> Void

    private var images: [ChatImagePayload] {
        ChatImagePayloadBuilder.imagePayloads(from: payload.imageAttachments)
    }

    private var files: [ChatAttachment] {
        payload.fileAttachments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) {
                cardHeader
            }
            .buttonStyle(.plain)

            if images.isEmpty == false {
                ChatImageGalleryBlockView(
                    images: images,
                    fileTransferService: fileTransferService,
                    style: .user
                )
            }

            if files.isEmpty == false {
                ChatFileAttachmentBlockView(
                    attachments: files,
                    role: .assistant,
                    fileTransferService: fileTransferService
                )
            }

            Button(action: onTap) {
                cardFooter
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("线上问诊，\(payload.consultNo)，点击查看详情")
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(payload.doctor?.displayName ?? payload.agent.name ?? "问诊医生")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let title = payload.doctor?.title, title.isEmpty == false {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ConsultationStatusText.label(for: payload.serviceStatus))
                    .font(.caption)
                    .foregroundStyle(ConsultationStatusText.color(for: payload.serviceStatus))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ConsultationStatusText.color(for: payload.serviceStatus).opacity(0.12))
                    .clipShape(Capsule())
            }
            Text([payload.department?.name, payload.hospital?.shortName ?? payload.hospital?.name]
                .compactMap { $0 }
                .filter { $0.isEmpty == false }
                .joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if payload.chiefComplaint.isEmpty == false {
                Text("主诉：\(payload.chiefComplaint)")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var cardFooter: some View {
        HStack(spacing: 10) {
            Text("问诊编号：\(payload.consultNo)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if let submittedAt = payload.submittedAt {
                Text(submittedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}
