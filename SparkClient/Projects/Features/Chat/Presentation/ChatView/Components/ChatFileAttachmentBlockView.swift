import SwiftUI

struct ChatFileAttachmentBlockView: View {
    let attachments: [ChatAttachment]
    let role: ChatMessageRole
    let fileTransferService: FileTransferService

    @State private var localFiles: [UUID: URL] = [:]
    @State private var downloadingIDs: Set<UUID> = []
    @State private var showUnifiedFilePreview = false
    @State private var previewInputs: [FilePreviewInput] = []
    @State private var previewIndex: Int = 0

    var body: some View {
        VStack(spacing: 8) {
            ForEach(attachments, id: \.id) { attachment in
                attachmentCard(attachment)
            }
        }
        .unifiedFilePreview(
            isPresented: $showUnifiedFilePreview,
            inputs: previewInputs,
            startIndex: previewIndex
        )
    }

    private func attachmentCard(_ attachment: ChatAttachment) -> some View {
        let name = displayName(for: attachment)
        let subtitle = localFiles[attachment.id] == nil
            ? L10n.text("chat.attachments.file.tap_to_download")
            : L10n.text("chat.attachments.file.tap_to_preview")
        return Button {
            Task { await handleTap(for: attachment) }
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(iconBackground)
                        .frame(width: 52, height: 52)
                    Image(systemName: attachment.type == .pdf ? "doc.richtext.fill" : "doc.fill")
                        .font(.title3)
                        .foregroundStyle(iconForeground)
                    Text(fileExtension(for: name))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.14)))
                        .foregroundStyle(iconForeground)
                        .offset(x: 6, y: 6)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textForeground)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(secondaryForeground)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if downloadingIDs.contains(attachment.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: localFiles[attachment.id] == nil ? "arrow.down.circle" : "eye")
                        .foregroundStyle(secondaryForeground)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(role == .user ? Color.white.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .task(id: attachment.imageDownloadDedupeKey) {
            await cacheLocalURLIfPresent(for: attachment)
        }
    }

    private var iconBackground: Color {
        role == .user ? Color.white.opacity(0.14) : Color.accentColor.opacity(0.12)
    }

    private var iconForeground: Color {
        role == .user ? .white : .accentColor
    }

    private var textForeground: Color {
        role == .user ? .white : .primary
    }

    private var secondaryForeground: Color {
        role == .user ? Color.white.opacity(0.82) : .secondary
    }

    @MainActor
    private func cacheLocalURLIfPresent(for attachment: ChatAttachment) async {
        guard let managedFile = attachment.managedFileRecordForDownload() else { return }
        if let cached = await fileTransferService.cachedURL(file: managedFile) {
            localFiles[attachment.id] = cached
        }
    }

    @MainActor
    private func handleTap(for attachment: ChatAttachment) async {
        guard let tappedIndex = attachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        let inputs = await buildPreviewInputs()
        await MainActor.run {
            guard inputs.isEmpty == false else { return }
            previewInputs = inputs
            previewIndex = min(max(0, tappedIndex), inputs.count - 1)
            showUnifiedFilePreview = true
        }
    }

    @MainActor
    private func buildPreviewInputs() async -> [FilePreviewInput] {
        var result: [FilePreviewInput] = []
        result.reserveCapacity(attachments.count)
        for attachment in attachments {
            if let input = await previewInput(for: attachment) {
                result.append(input)
            }
        }
        return result
    }

    @MainActor
    private func previewInput(for attachment: ChatAttachment) async -> FilePreviewInput? {
        if let local = localFiles[attachment.id] {
            return FilePreviewInput(
                id: attachment.id,
                fileURL: local,
                displayName: displayName(for: attachment),
                mimeType: FileUtilities.mimeType(forName: displayName(for: attachment))
            )
        }
        guard let managedFile = attachment.managedFileRecordForDownload() else { return Self.previewUnavailableInput(for: attachment) }

        downloadingIDs.insert(attachment.id)
        defer { downloadingIDs.remove(attachment.id) }

        if let cached = await fileTransferService.cachedURL(file: managedFile) {
            localFiles[attachment.id] = cached
            return FilePreviewInput(
                id: attachment.id,
                fileURL: cached,
                displayName: displayName(for: attachment),
                mimeType: FileUtilities.mimeType(forName: displayName(for: attachment))
            )
        }

        do {
            let local = try await fileTransferService.download(file: managedFile)
            localFiles[attachment.id] = local
            return FilePreviewInput(
                id: attachment.id,
                fileURL: local,
                displayName: displayName(for: attachment),
                mimeType: FileUtilities.mimeType(forName: displayName(for: attachment))
            )
        } catch {
            return Self.previewUnavailableInput(for: attachment)
        }
    }

    private static func previewUnavailableInput(for attachment: ChatAttachment) -> FilePreviewInput {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-preview-missing-\(attachment.id.uuidString)")
        return FilePreviewInput(
            id: attachment.id,
            fileURL: url,
            displayName: "Preview unavailable",
            mimeType: nil
        )
    }

    private func displayName(for attachment: ChatAttachment) -> String {
        if let parsed = attachment.sparkClientOSSFileUUIDAndFileName() {
            return parsed.fileName
        }
        if let name = attachment.url?.lastPathComponent.removingPercentEncoding,
           name.isEmpty == false {
            return name
        }
        return attachment.type == .pdf ? "document.pdf" : "attachment"
    }

    private func fileExtension(for name: String) -> String {
        let ext = (name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }
}
