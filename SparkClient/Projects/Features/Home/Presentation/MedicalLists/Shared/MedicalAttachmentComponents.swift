import SwiftUI

/// 医疗附件入口图标：参考 HealthClient 的附件角标样式，作为各类卡片统一入口。
struct MedicalAttachmentIconView: View {
    let count: Int
    var isExpanded = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Image(systemName: isExpanded ? "paperclip.circle.fill" : "paperclip")
                        .font(.title3)
                        .foregroundStyle(count > 0 ? Color.accentColor : .secondary)
                    Text(L10n.text("home.medical.attachments.title"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 2)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 8, y: -4)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count > 0 ? 1 : 0.55)
    }
}

/// 医疗附件列表：点击时自动命中缓存或下载后通过统一预览模块打开。
struct MedicalAttachmentListView: View {
    let attachments: [SparkMedicalSyncAPI.RemoteManagedFile]
    let fileTransferService: FileTransferService
    var logger: Logger = ConsoleLogger()

    @State private var previewInput: FilePreviewInput?
    @State private var downloadingIDs: Set<Int> = []

    private let logModule = LogModule.home

    var body: some View {
        VStack(spacing: 8) {
            ForEach(attachments, id: \.id) { attachment in
                Button {
                    Task {
                        await openAttachment(attachment)
                    }
                } label: {
                    attachmentRow(attachment)
                }
                .buttonStyle(.plain)
                .disabled(downloadingIDs.contains(attachment.id))
            }
        }
        .unifiedFilePreview(selection: $previewInput)
    }

    private func attachmentRow(_ attachment: SparkMedicalSyncAPI.RemoteManagedFile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 40, height: 40)
                Image(systemName: attachment.symbolName)
                    .font(.headline)
                    .foregroundStyle(attachment.tintColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let sizeText = attachment.fileSizeText {
                        Text(sizeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if let mimeText = attachment.mimeType?.nonEmpty {
                        Text(mimeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if downloadingIDs.contains(attachment.id) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.85))
        )
    }

    @MainActor
    private func openAttachment(_ attachment: SparkMedicalSyncAPI.RemoteManagedFile) async {
        guard let managedFile = attachment.managedFileRecord else {
            logger.warning("附件打开失败，缺少必要字段 attachmentID=\(attachment.id)", module: logModule)
            return
        }

        if let cachedURL = await fileTransferService.cachedURL(file: managedFile) {
            previewInput = FilePreviewInput(
                fileURL: cachedURL,
                displayName: attachment.displayName,
                mimeType: attachment.mimeType
            )
            return
        }

        downloadingIDs.insert(attachment.id)
        defer { downloadingIDs.remove(attachment.id) }

        do {
            let localURL = try await fileTransferService.download(file: managedFile)
            previewInput = FilePreviewInput(
                fileURL: localURL,
                displayName: attachment.displayName,
                mimeType: attachment.mimeType
            )
            logger.info("附件预览已打开 attachmentID=\(attachment.id)", module: logModule)
        } catch {
            logger.warning("附件下载失败 attachmentID=\(attachment.id) error=\(error.localizedDescription)", module: logModule)
        }
    }
}

extension SparkMedicalSyncAPI.RemoteManagedFile {
    var managedFileRecord: ManagedFileRecord? {
        guard let fileUUID = fileUuid?.nonEmpty else { return nil }
        return ManagedFileRecord(
            id: id,
            fileUUID: fileUUID,
            filePath: fileUrl?.nonEmpty ?? objectKey?.nonEmpty,
            originalName: displayName,
            fileSize: fileSize ?? 0,
            mimeType: mimeType?.nonEmpty ?? "application/octet-stream",
            fileMd5: fileMd5?.nonEmpty,
            isPublic: false,
            businessType: businessType?.nonEmpty ?? "medical_attachment",
            businessID: businessId?.nonEmpty ?? "",
            createdAt: createdAt.map(Self.createdAtFormatter.string(from:)) ?? "",
            objectKey: objectKey?.nonEmpty,
            storageType: storageType?.nonEmpty
        )
    }

    var displayName: String {
        originalName?.nonEmpty ?? "Attachment-\(id)"
    }

    var fileSizeText: String? {
        guard let fileSize, fileSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var symbolName: String {
        let ext = (displayName as NSString).pathExtension.lowercased()
        let mime = mimeType?.lowercased() ?? ""
        if mime.contains("pdf") || ext == "pdf" {
            return "doc.richtext"
        }
        if mime.contains("image") || ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
            return "photo"
        }
        if mime.contains("sheet") || ["xls", "xlsx", "csv"].contains(ext) {
            return "tablecells"
        }
        return "doc"
    }

    var tintColor: Color {
        let ext = (displayName as NSString).pathExtension.lowercased()
        let mime = mimeType?.lowercased() ?? ""
        if mime.contains("pdf") || ext == "pdf" {
            return Color(uiColor: .systemRed)
        }
        if mime.contains("image") || ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
            return Color(uiColor: .systemBlue)
        }
        if mime.contains("sheet") || ["xls", "xlsx", "csv"].contains(ext) {
            return Color(uiColor: .systemGreen)
        }
        return Color(uiColor: .systemIndigo)
    }

    private static let createdAtFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
