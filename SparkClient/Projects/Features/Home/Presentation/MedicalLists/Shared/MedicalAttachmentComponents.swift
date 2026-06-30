import Combine
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
                    Text(L10n.text("common.attachments"))
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
            fileUuid: fileUUID,
            filePath: fileUrl?.nonEmpty ?? objectKey?.nonEmpty,
            originalName: displayName,
            fileSize: fileSize ?? 0,
            mimeType: mimeType?.nonEmpty ?? "application/octet-stream",
            fileMd5: fileMd5?.nonEmpty,
            isPublic: false,
            businessType: businessType?.nonEmpty ?? "medical_attachment",
            businessId: businessId?.nonEmpty ?? "",
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

extension ManagedFileRecord {
    func remoteManagedFile(businessType: String? = nil, businessId: String? = nil) -> SparkMedicalSyncAPI.RemoteManagedFile {
        SparkMedicalSyncAPI.RemoteManagedFile(
            id: id,
            fileUuid: fileUuid,
            originalName: originalName,
            fileSize: fileSize,
            mimeType: mimeType,
            fileMd5: fileMd5,
            businessType: businessType ?? self.businessType,
            businessId: businessId ?? self.businessId,
            objectKey: objectKey,
            storageType: storageType,
            createdAt: ISO8601DateFormatter().date(from: createdAt),
            fileUrl: filePath
        )
    }
}



// MARK: - 附件上传协调器

/// 管理 MedicalAttachmentGridPreview 内单张附件的上传进度与状态。
@MainActor
private final class AttachmentUploadCoordinator: ObservableObject, @unchecked Sendable {
    struct Card: Identifiable {
        let id: UUID
        let file: MedicalUploadLocalFile
        var progress: Double = 0
        var errorMessage: String? = nil

        var isImage: Bool {
            let ext = (file.displayName as NSString).pathExtension.lowercased()
            return file.mimeType?.contains("image") == true
                || ["png", "jpg", "jpeg", "heic", "webp"].contains(ext)
        }
    }

    @Published var cards: [Card] = []

    func addCard(file: MedicalUploadLocalFile) -> UUID {
        let id = UUID()
        cards.append(Card(id: id, file: file))
        return id
    }

    func updateProgress(id: UUID, progress: Double) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[idx].progress = progress
    }

    func markError(id: UUID, message: String) {
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[idx].errorMessage = message
    }

    func removeCard(id: UUID) {
        cards.removeAll { $0.id == id }
    }
}

/// 医疗附件操作失败提示：优先使用服务端 `msg`/`code` 对应的中文文案。
enum MedicalAttachmentErrorMessage {
    static func deleteFailed(from error: Error) -> String {
        formatted(
            templateKey: "home.medical.attachment.delete_failed",
            templateFallback: "删除附件失败：%@",
            error: error
        )
    }

    static func uploadFailed(from error: Error) -> String {
        formatted(
            templateKey: "home.medical.attachment.upload_failed_with_reason",
            templateFallback: "上传附件失败：%@",
            error: error
        )
    }

    private static func formatted(templateKey: String, templateFallback: String, error: Error) -> String {
        let reason = backendMessage(from: error)
        return String(format: L10n.text(templateKey, fallback: templateFallback), reason)
    }

    private static func backendMessage(from error: Error) -> String {
        if let networkError = error as? SparkNetworkError,
           case let .httpError(statusCode, backend, _) = networkError {
            return BackendErrorLocalizer.message(for: backend, statusCode: statusCode)
        }
        return error.localizedDescription
    }
}

/// 医疗附件网格预览：自动下载 + 网格展示 + 点击预览。
/// 编辑模式下支持删除附件（内部调用服务端）与上传新附件（单卡片上传进度）。
struct MedicalAttachmentGridPreview: View {
    let attachments: [SparkMedicalSyncAPI.RemoteManagedFile]
    let fileTransferService: FileTransferService
    var logger: Logger = ConsoleLogger()
    var isEditing: Bool = false
    /// 删除成功后回调已删除的 fileID，调用方负责更新本地数据源。
    var onDeleted: ((Int) -> Void)? = nil
    /// 上传成功后回调 ManagedFileRecord；调用方负责 updateBusinessBinding 及追加业务记录。
    var onFileUploaded: ((ManagedFileRecord) -> Void)? = nil

    @StateObject private var uploadCoordinator = AttachmentUploadCoordinator()
    @State private var selectedAttachmentID: Int?
    @State private var downloadingIDs: Set<Int> = []
    @State private var deletingIDs: Set<Int> = []
    @State private var cachedFileURLs: [Int: URL] = [:]
    @State private var pendingDeleteFileID: Int?
    @State private var deleteErrorMessage: String?

    private let logModule = LogModule.home

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 12
        ) {
            ForEach(attachments, id: \.id) { attachment in
                attachmentGridCard(attachment)
                    .onTapGesture {
                        guard isEditing == false else { return }
                        Task { await openAttachment(attachment) }
                    }
                    .disabled(downloadingIDs.contains(attachment.id) || deletingIDs.contains(attachment.id))
            }

            ForEach(uploadCoordinator.cards) { card in
                uploadingCardView(card: card)
            }

            if isEditing, onFileUploaded != nil {
                addAttachmentCell
            }
        }
        // GeometryReader 在 LazyVGrid 内会撑高布局，clipped() 防止内容溢出遮挡父视图的触控区域
        .clipped()
        .unifiedFilePreview(
            isPresented: Binding(
                get: { selectedAttachmentID != nil },
                set: { if !$0 { selectedAttachmentID = nil } }
            ),
            inputs: previewInputs,
            startIndex: selectedPreviewIndex
        )
        .onAppear {
            Task { await downloadAllAttachmentsAutomatically() }
        }
        .onChange(of: attachmentIDs) { _ in
            Task { await downloadAllAttachmentsAutomatically() }
        }
        .alert(
            L10n.text("home.medical.attachment.delete_confirm_title", fallback: "确认删除此附件？"),
            isPresented: Binding(
                get: { pendingDeleteFileID != nil },
                set: { if !$0 { pendingDeleteFileID = nil } }
            )
        ) {
            Button(L10n.text("common.cancel"), role: .cancel) {
                pendingDeleteFileID = nil
            }
            Button(L10n.text("common.delete"), role: .destructive) {
                if let fileID = pendingDeleteFileID {
                    performDelete(fileID: fileID)
                }
                pendingDeleteFileID = nil
            }
        } message: {
            Text(L10n.text("home.medical.attachment.delete_confirm_message", fallback: "删除后无法恢复。"))
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(L10n.text("common.got_it"), role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }
}

private extension MedicalAttachmentGridPreview {
    var attachmentIDs: [Int] {
        attachments.map(\.id)
    }

    var previewInputs: [FilePreviewInput] {
        attachments.compactMap { attachment in
            guard let localURL = cachedFileURLs[attachment.id] else { return nil }
            return FilePreviewInput(
                fileURL: localURL,
                displayName: attachment.displayName,
                mimeType: attachment.mimeType
            )
        }
    }

    var selectedPreviewIndex: Int {
        guard let selectedAttachmentID else { return 0 }
        var index = 0
        for attachment in attachments {
            guard cachedFileURLs[attachment.id] != nil else { continue }
            if attachment.id == selectedAttachmentID { return index }
            index += 1
        }
        return 0
    }
}

// MARK: - UI 卡片
extension MedicalAttachmentGridPreview {
    @ViewBuilder
    private var addAttachmentCell: some View {
        if onFileUploaded != nil {
            MedicalDocumentFilePickerMenu(maxPhotoSelectionCount: 1) {
                addPlaceholderCard
            } onFilesSelected: { files in
                if let file = files.first {
                    startUpload(file: file)
                }
            }
        }
    }

    private var addPlaceholderCard: some View {
        GeometryReader { geometry in
            let cardSize = geometry.size.width
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: min(cardSize * 0.28, 28), weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(L10n.text("common.add"))
                    .font(.system(size: min(cardSize * 0.11, 11)))
                    .foregroundStyle(.secondary)
            }
            .frame(width: cardSize, height: cardSize)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .contentShape(Rectangle())
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func uploadingCardView(card: AttachmentUploadCoordinator.Card) -> some View {
        GeometryReader { geometry in
            let cardSize = geometry.size.width
            ZStack {
                // 背景：本地图片预览 / 纯色占位
                if card.isImage {
                    LocalFileImageThumbnail(url: card.file.url)
                        .frame(width: cardSize, height: cardSize)
                        .clipped()
                } else {
                    Color(uiColor: .tertiarySystemFill)
                        .frame(width: cardSize, height: cardSize)
                }

                // 半透明遮罩
                Color.black.opacity(0.42)

                if card.errorMessage != nil {
                    // 上传失败态
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: min(cardSize * 0.28, 28)))
                            .foregroundStyle(.white)
                        Text(L10n.text("home.medical.attachment.upload_failed", fallback: "上传失败"))
                            .font(.system(size: min(cardSize * 0.10, 10)))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Button {
                            uploadCoordinator.removeCard(id: card.id)
                        } label: {
                            Text(L10n.text("common.dismiss", fallback: "关闭"))
                                .font(.system(size: min(cardSize * 0.10, 10), weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.25), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // 上传进度环
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: CGFloat(card.progress))
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.12), value: card.progress)
                        }
                        .frame(width: min(cardSize * 0.42, 44), height: min(cardSize * 0.42, 44))

                        Text("\(Int(card.progress * 100))%")
                            .font(.system(size: min(cardSize * 0.11, 11)).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 网格正方形卡片（已有附件 · 下载/删除状态 + 编辑删除按钮）
    private func attachmentGridCard(_ attachment: SparkMedicalSyncAPI.RemoteManagedFile) -> some View {
        GeometryReader { geometry in
            let cardSize = geometry.size.width

            ZStack(alignment: .topTrailing) {
                // 删除中
                if deletingIDs.contains(attachment.id) {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.large)
                        Text(L10n.text("home.medical.attachment.deleting", fallback: "删除中…"))
                            .font(.system(size: min(cardSize * 0.11, 11)))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: cardSize, height: cardSize)
                    .background(Color(uiColor: .tertiarySystemFill))
                }
                // 下载中
                else if downloadingIDs.contains(attachment.id) {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.large)
                        Text("下载中...")
                            .font(.system(size: min(cardSize * 0.11, 11)))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: cardSize, height: cardSize)
                    .background(Color(uiColor: .tertiarySystemFill))
                }
                // 已下载
                else if let localURL = cachedFileURLs[attachment.id] {
                    let previewItem = FilePreviewInput(
                        fileURL: localURL,
                        displayName: attachment.displayName,
                        mimeType: attachment.mimeType
                    )
                    if previewItem.isImage {
                        LocalFileImageThumbnail(url: localURL)
                            .frame(width: cardSize, height: cardSize)
                            .clipped()
                            .background(Color(uiColor: .tertiarySystemFill))

                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: attachment.symbolName)
                                .font(.system(size: min(cardSize * 0.3, 32)))
                                .foregroundStyle(attachment.tintColor)
                            Text(attachment.displayName)
                                .font(.system(size: min(cardSize * 0.11, 11)))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: cardSize, height: cardSize)
                        .background(
                            LinearGradient(
                                colors: [attachment.tintColor.opacity(0.10), Color(.systemIndigo).opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                // 未下载
                else {
                    VStack(spacing: 8) {
                        Image(systemName: attachment.symbolName)
                            .font(.system(size: min(cardSize * 0.3, 32)))
                            .foregroundStyle(attachment.tintColor)
                        Text(attachment.displayName)
                            .font(.system(size: min(cardSize * 0.11, 11)))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: cardSize, height: cardSize)
                    .background(Color(uiColor: .tertiarySystemFill))
                }

                if isEditing, onDeleted != nil, !deletingIDs.contains(attachment.id) {
                    Button {
                        pendingDeleteFileID = attachment.id
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(uiColor: .systemRed))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .frame(width: cardSize, height: cardSize)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // contentShape 把 hit-test 区域严格限定在卡片方块内，防止图片超出部分拦截上方视图的点击
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 删除逻辑
extension MedicalAttachmentGridPreview {
    private func performDelete(fileID: Int) {
        guard !deletingIDs.contains(fileID) else { return }
        deletingIDs.insert(fileID)
        Task { @MainActor in
            do {
                try await fileTransferService.delete(fileID: fileID)
                deletingIDs.remove(fileID)
                onDeleted?(fileID)
            } catch {
                deletingIDs.remove(fileID)
                deleteErrorMessage = MedicalAttachmentErrorMessage.deleteFailed(from: error)
                logger.warning("附件删除失败 fileID=\(fileID) error=\(error.localizedDescription)", module: logModule)
            }
        }
    }
}

// MARK: - 上传逻辑
extension MedicalAttachmentGridPreview {
    private func startUpload(file: MedicalUploadLocalFile) {
        let cardID = uploadCoordinator.addCard(file: file)
        let coordinator = uploadCoordinator

        Task { @MainActor in
            do {
                let data = try Data(contentsOf: file.url)
                let record = try await fileTransferService.upload(
                    ManagedFileUploadPayload(
                        data: data,
                        fileName: file.displayName,
                        businessType: "medical_attachment",
                        businessId: "",
                        isPublic: false,
                        onUploadProgress: { @Sendable progress in
                            Task { @MainActor in
                                coordinator.updateProgress(id: cardID, progress: progress)
                            }
                        }
                    )
                )
                coordinator.removeCard(id: cardID)
                cachedFileURLs[record.id] = file.url
                onFileUploaded?(record)
            } catch {
                coordinator.markError(id: cardID, message: MedicalAttachmentErrorMessage.uploadFailed(from: error))
                logger.warning("附件上传失败 error=\(error.localizedDescription)", module: logModule)
            }
        }
    }
}

// MARK: - 下载 & 预览逻辑
extension MedicalAttachmentGridPreview {
    @MainActor
    private func downloadAllAttachmentsAutomatically() async {
        guard !attachments.isEmpty else { return }
        for attachment in attachments {
            Task { await downloadSingleAttachmentIfNeeded(attachment) }
        }
    }

    @MainActor
    private func downloadSingleAttachmentIfNeeded(_ attachment: SparkMedicalSyncAPI.RemoteManagedFile) async {
        guard let managedFile = attachment.managedFileRecord else { return }
        guard !downloadingIDs.contains(attachment.id), cachedFileURLs[attachment.id] == nil else { return }

        downloadingIDs.insert(attachment.id)
        defer { downloadingIDs.remove(attachment.id) }

        if let cachedURL = await fileTransferService.cachedURL(file: managedFile) {
            cachedFileURLs[attachment.id] = cachedURL
            return
        }

        do {
            let localURL = try await fileTransferService.download(file: managedFile)
            cachedFileURLs[attachment.id] = localURL
            logger.info("自动下载完成 attachmentID=\(attachment.id)", module: logModule)
        } catch {
            logger.warning("自动下载失败 attachmentID=\(attachment.id)", module: logModule)
        }
    }

    @MainActor
    private func openAttachment(_ attachment: SparkMedicalSyncAPI.RemoteManagedFile) async {
        if cachedFileURLs[attachment.id] != nil {
            selectedAttachmentID = attachment.id
            return
        }
        await downloadSingleAttachmentIfNeeded(attachment)
        if cachedFileURLs[attachment.id] != nil {
            selectedAttachmentID = attachment.id
        }
    }
}
