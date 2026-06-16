import SwiftUI

/// 时间轴卡片内的附件胶囊按钮：点击后走与 `MedicalAttachmentListView` 相同的缓存/下载预览流程。
struct MedicalCaseAttachmentPill: View {
    let attachment: SparkMedicalSyncAPI.RemoteManagedFile
    let fileTransferService: FileTransferService

    var logger: Logger = ConsoleLogger()

    @State private var previewInput: FilePreviewInput?
    @State private var isBusy = false

    private let logModule = LogModule.home

    var body: some View {
        Button {
            Task { await openAttachment() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: attachment.symbolName)
                    .font(.caption2)
                    .symbolRenderingMode(.hierarchical)

                Text(attachment.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.28), lineWidth: 1))
            )
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .overlay {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .unifiedFilePreview(
            isPresented: Binding(
                get: { previewInput != nil },
                set: { isPresented in
                    if isPresented == false {
                        previewInput = nil
                    }
                }
            ),
            inputs: previewInput.map { [$0] } ?? []
        )
    }

    @MainActor
    private func openAttachment() async {
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

        isBusy = true
        defer { isBusy = false }

        do {
            let localURL = try await fileTransferService.download(file: managedFile)
            previewInput = FilePreviewInput(
                fileURL: localURL,
                displayName: attachment.displayName,
                mimeType: attachment.mimeType
            )
        } catch {
            logger.warning("附件下载失败 attachmentID=\(attachment.id) error=\(error.localizedDescription)", module: logModule)
        }
    }
}

#Preview("Attachment pill — Light") {
    let sample = SparkMedicalSyncAPI.RemoteManagedFile(
        id: 1,
        fileUuid: "00000000-0000-0000-0000-000000000001",
        originalName: "报告.pdf",
        fileSize: 2048,
        mimeType: "application/pdf",
        fileMd5: nil,
        businessType: "medical",
        businessId: "1",
        objectKey: "k",
        storageType: "oss",
        createdAt: Date(),
        fileUrl: nil
    )
    MedicalCaseAttachmentPill(attachment: sample, fileTransferService: AppContainer.preview.fileTransferService)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Attachment pill — Dark") {
    let sample = SparkMedicalSyncAPI.RemoteManagedFile(
        id: 1,
        fileUuid: "00000000-0000-0000-0000-000000000001",
        originalName: "报告.pdf",
        fileSize: 2048,
        mimeType: "application/pdf",
        fileMd5: nil,
        businessType: "medical",
        businessId: "1",
        objectKey: "k",
        storageType: "oss",
        createdAt: Date(),
        fileUrl: nil
    )
    MedicalCaseAttachmentPill(attachment: sample, fileTransferService: AppContainer.preview.fileTransferService)
        .padding()
        .preferredColorScheme(.dark)
}
