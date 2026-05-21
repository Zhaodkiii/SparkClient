import SwiftUI
import MapKit
import WebKit
import UIKit

struct ChatMapLocationPayload: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct ChatRoutePayload: Codable, Identifiable, Equatable {
    let id: UUID
    let summary: String
    let distance: String?
    let duration: String?
    let mode: String?

    init(
        id: UUID = UUID(),
        summary: String,
        distance: String? = nil,
        duration: String? = nil,
        mode: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.distance = distance
        self.duration = duration
        self.mode = mode
    }
}

struct ChatEventPayload: Codable, Identifiable, Equatable {
    let id: UUID
    let type: String
    let title: String
    let dateText: String?
    let location: String?
    let notes: String?

    init(
        id: UUID = UUID(),
        type: String,
        title: String,
        dateText: String? = nil,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.dateText = dateText
        self.location = location
        self.notes = notes
    }
}

struct ChatHealthCardPayload: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let energyKilocalories: Double?
    let proteinGrams: Double?
    let carbohydratesGrams: Double?
    let fatGrams: Double?
    let dateText: String?

    init(
        id: UUID = UUID(),
        title: String,
        energyKilocalories: Double? = nil,
        proteinGrams: Double? = nil,
        carbohydratesGrams: Double? = nil,
        fatGrams: Double? = nil,
        dateText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.energyKilocalories = energyKilocalories
        self.proteinGrams = proteinGrams
        self.carbohydratesGrams = carbohydratesGrams
        self.fatGrams = fatGrams
        self.dateText = dateText
    }
}

struct ChatTranslatedBlockView: View {
    let text: String
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(L10n.text("chat.bubble.translate.title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Markdown(text)
                    .markdownTheme(.chatBubble(foreground: .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }
}

struct ChatEventsCardListView: View {
    let events: [ChatEventPayload]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: event.type.lowercased() == "calendar" ? "calendar" : "list.bullet")
                            .foregroundStyle(.secondary)
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    if let dateText = event.dateText, dateText.isEmpty == false {
                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let location = event.location, location.isEmpty == false {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = event.notes, notes.isEmpty == false {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
            }
        }
    }
}

struct ChatHealthCardListView: View {
    let cards: [ChatHealthCardPayload]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        nutrient("kcal", card.energyKilocalories)
                        nutrient("P", card.proteinGrams)
                        nutrient("C", card.carbohydratesGrams)
                        nutrient("F", card.fatGrams)
                    }
                    if let dateText = card.dateText, dateText.isEmpty == false {
                        Text(dateText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
            }
        }
    }

    private func nutrient(_ key: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.1f", $0) } ?? "--")
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatMapRouteBlockView: View {
    let locations: [ChatMapLocationPayload]
    let routes: [ChatRoutePayload]
    @State private var mapType: MKMapType = .standard
    @State private var showFullMap = false

    private var region: MKCoordinateRegion {
        guard let first = locations.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatUIKitMapView(region: region, locations: locations, mapType: mapType)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    mapType = mapType == .standard ? .hybridFlyover : .standard
                } label: {
                    Label(L10n.text("chat.bubble.map.style"), systemImage: "map")
                        .font(.caption)
                }
                Button {
                    showFullMap = true
                } label: {
                    Label(L10n.text("chat.bubble.map.fullscreen"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                if let first = locations.first {
                    Button {
                        let name = first.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Destination"
                        if let url = URL(string: "http://maps.apple.com/?daddr=\(first.latitude),\(first.longitude)&q=\(name)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(L10n.text("chat.bubble.map.navigate"), systemImage: "location.north.line")
                            .font(.caption)
                    }
                }
            }

            if routes.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(routes) { route in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.summary)
                                .font(.caption.weight(.medium))
                            Text([route.distance, route.duration, route.mode]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { $0.isEmpty == false }
                                .joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFullMap) {
            ChatUIKitMapView(region: region, locations: locations, mapType: mapType)
                .ignoresSafeArea()
        }
    }
}

struct ChatHTMLPreviewBlockView: View {
    let htmlContent: String
    @State private var showFull = false
    @State private var showSource = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ChatHTMLWebView(htmlContent: htmlContent)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    showSource = true
                } label: {
                    Image(systemName: "chevron.left.slash.chevron.right")
                }
                Button {
                    showFull = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }
            .font(.caption)
            .padding(8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
        }
        .sheet(isPresented: $showSource) {
            CompatibleNavigationContainer(legacyStackStyle: true) {
                ScrollView {
                    Text(htmlContent)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(L10n.text("chat.bubble.web.source"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(L10n.text("chat.bubble.action.copy")) {
                            UIPasteboard.general.string = htmlContent
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showFull) {
            CompatibleNavigationContainer(legacyStackStyle: true) {
                ChatHTMLWebView(htmlContent: htmlContent)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(L10n.text("common.close")) {
                                showFull = false
                            }
                        }
                    }
            }
        }
    }
}

/// 从消息附件构建画廊用图片载荷（`type == .image`：`url`、本地缓存、或 `text` 中的内嵌图 / http(s) 片段）。
enum ChatImagePayloadBuilder {
    static func imagePayloads(from message: ChatMessage) -> [ChatImagePayload] {
        var payloads: [ChatImagePayload] = []
        let attachments = message.blocks
            .filter { $0.kind == .imageGallery || $0.kind == .fileAttachments }
            .flatMap(\.attachments)
        for attachment in attachments where attachment.isChatImageLike {
            if let image = ChatAttachment.inlinePreviewUIImage(from: attachment) {
                payloads.append(ChatImagePayload(id: attachment.id, url: nil, image: image, managedFile: nil))
                continue
            }

            if let parsed = attachment.sparkClientOSSFileUUIDAndFileName(),
               let img = ChatLocalImageCache.uiImageIfCached(fileUUID: parsed.fileUUID, originalName: parsed.fileName) {
                payloads.append(ChatImagePayload(id: attachment.id, url: nil, image: img, managedFile: nil))
                continue
            }

            guard let downloadURL = attachment.resolvedHTTPSImageDownloadURL() else { continue }
            let managedFile = attachment.managedFileRecord(downloadURL: downloadURL)

            payloads.append(
                ChatImagePayload(
                    id: attachment.id,
                    url: downloadURL,
                    image: nil,
                    managedFile: managedFile
                )
            )
            ChatAttachmentImageDiagnostics.debug(
                "payloadBuilder.remote id=\(attachment.id.uuidString.prefix(8)) url=\(downloadURL.absoluteString)"
            )
        }
//        ChatAttachmentImageDiagnostics.debug("payloadBuilder.done count=\(payloads.count)")
        return payloads
    }

}

struct ChatImagePayload: Identifiable, Equatable {
    let id: UUID
    let url: URL?
    let image: UIImage?
    /// 远程图下载用记录（构建载荷时已固化，对齐医疗 ``managedFileRecord``）。
    let managedFile: ManagedFileRecord?
}

/// 对齐 `AI_HLY` 的聊天图片条：用户消息约 `120×120`、助手约 `200×200`，横向滚动与圆角卡片；点击预览统一走 `UnifiedFilePreview`。
enum ChatImageGalleryStyle {
    case user
    case assistant

    fileprivate var thumbSide: CGFloat {
        switch self {
        case .user: return 120
        case .assistant: return 200
        }
    }

    fileprivate var spacing: CGFloat {
        switch self {
        case .user: return 6
        case .assistant: return 8
        }
    }

    fileprivate var cornerRadius: CGFloat { 14 }
}

struct ChatImageGalleryBlockView: View {
    let images: [ChatImagePayload]
    let fileTransferService: FileTransferService
    var style: ChatImageGalleryStyle = .user
    var unifiedFilePreview: Binding<FilePreviewInput?>?
    @State private var downloadingImageIDs: Set<UUID> = []
    @State private var downloadedImageFiles: [UUID: URL] = [:]
    @State private var autoTriggeredImageIDs: Set<UUID> = []
    @State private var failedImageIDs: Set<UUID> = []

    init(
        images: [ChatImagePayload],
        fileTransferService: FileTransferService,
        style: ChatImageGalleryStyle = .user,
        unifiedFilePreview: Binding<FilePreviewInput?>? = nil
    ) {
        self.images = images
        self.fileTransferService = fileTransferService
        self.style = style
        self.unifiedFilePreview = unifiedFilePreview
    }

    private var galleryWidth: CGFloat {
        let count = Double(images.count)
        let cell = style.thumbSide + style.spacing
        return CGFloat(min(count, 2.5) * Double(cell) - Double(style.spacing))
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: style.spacing) {
                ForEach(images) { payload in
                    galleryCell(for: payload)
                }
            }
        }
        .frame(width: galleryWidth, height: style.thumbSide)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        /// 画廊块进入可视区时按需拉取（对齐医疗附件网格 `onAppear` 懒加载，非列表级批量下载）。
        .onAppear {
            ChatAttachmentImageDiagnostics.debug("gallery.onAppear imageCount=\(images.count)")
            for payload in images {
                Task {
                    await loadImageIfNeeded(for: payload, reason: "gallery.onAppear")
                }
            }
        }
    }

    @ViewBuilder
    private func galleryCell(for payload: ChatImagePayload) -> some View {
        let isFailed = failedImageIDs.contains(payload.id)

        Group {
            if isFailed, payload.url != nil {
                failedDownloadCell(for: payload)
            } else {
                loadedOrLoadingCell(for: payload)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await openPreview(for: payload)
                        }
                    }
            }
        }
        .frame(width: style.thumbSide, height: style.thumbSide)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .contextMenu {
            contextButtons(for: payload)
        }
    }

    @ViewBuilder
    private func loadedOrLoadingCell(for payload: ChatImagePayload) -> some View {
        ZStack {
            if let local = downloadedImageFiles[payload.id], let image = UIImage(contentsOfFile: local.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let image = payload.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if payload.managedFile != nil {
                loadingPlaceholder
            } else if let url = payload.url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                    @unknown default:
                        Image(systemName: "photo")
                    }
                }
            } else {
                Image(systemName: "photo")
            }
        }
    }

    private var loadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.regular)
                Text(L10n.text("chat.bubble.image.loading"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 失败态独立视图，避免外层 `onTapGesture` 抢占「重试」按钮点击。
    private func failedDownloadCell(for payload: ChatImagePayload) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await retryDownload(for: payload)
                    }
                } label: {
                    Label(L10n.text("common.retry"), systemImage: "arrow.clockwise.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(6)
        }
    }

    @MainActor
    private func retryDownload(for payload: ChatImagePayload) async {
        ChatAttachmentImageDiagnostics.info(
            "gallery.retryTap payloadID=\(payload.id.uuidString.prefix(8))"
        )
        failedImageIDs.remove(payload.id)
        autoTriggeredImageIDs.remove(payload.id)
        do {
            _ = try await ensureLocalFile(for: payload, reason: "gallery.retry")
        } catch {
            failedImageIDs.insert(payload.id)
            ChatAttachmentImageDiagnostics.warning(
                "gallery.retryFailed payloadID=\(payload.id.uuidString.prefix(8)) error=\(ChatAttachmentImageDiagnostics.errorDescription(error))"
            )
        }
    }

    @ViewBuilder
    private func contextButtons(for payload: ChatImagePayload) -> some View {
        Button(L10n.text("chat.bubble.image.copy"), systemImage: "square.on.square") {
            Task {
                await copyImage(payload)
            }
        }
        Button(L10n.text("chat.bubble.image.save"), systemImage: "square.and.arrow.down") {
            Task {
                await saveImage(payload)
            }
        }
    }

    private func copyImage(_ payload: ChatImagePayload) async {
        if let image = payload.image {
            await MainActor.run { UIPasteboard.general.image = image }
            return
        }
        if let local = downloadedImageFiles[payload.id], let image = UIImage(contentsOfFile: local.path) {
            await MainActor.run { UIPasteboard.general.image = image }
            return
        }
        if payload.url != nil {
            do {
                let local = try await ensureLocalFile(for: payload, reason: "gallery.copy")
                if let image = UIImage(contentsOfFile: local.path) {
                    await MainActor.run { UIPasteboard.general.image = image }
                }
            } catch {}
            return
        }
        guard let url = payload.url else { return }
        if let data = try? await downloadData(from: url), let image = UIImage(data: data) {
            await MainActor.run { UIPasteboard.general.image = image }
        }
    }

    private func saveImage(_ payload: ChatImagePayload) async {
        if let image = payload.image {
            await MainActor.run { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
            return
        }
        if let local = downloadedImageFiles[payload.id], let image = UIImage(contentsOfFile: local.path) {
            await MainActor.run { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
            return
        }
        if payload.url != nil {
            do {
                let local = try await ensureLocalFile(for: payload, reason: "gallery.save")
                if let image = UIImage(contentsOfFile: local.path) {
                    await MainActor.run { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
                }
            } catch {}
            return
        }
        guard let url = payload.url else { return }
        if let data = try? await downloadData(from: url), let image = UIImage(data: data) {
            await MainActor.run { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
        }
    }

    private func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) == false {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// 统一预览入口：本地图片写入临时 JPEG；远程先下载再交给 `UnifiedFilePreview` / Quick Look。
    private func openPreview(for payload: ChatImagePayload) async {
        guard let binding = unifiedFilePreview else { return }

        if let local = downloadedImageFiles[payload.id] {
            await MainActor.run {
                binding.wrappedValue = FilePreviewInput(
                    fileURL: local,
                    displayName: local.lastPathComponent,
                    mimeType: nil
                )
            }
            return
        }

        if let image = payload.image,
           let tmp = Self.writeTempJPEG(image) {
            await MainActor.run {
                binding.wrappedValue = FilePreviewInput(
                    fileURL: tmp,
                    displayName: "chat-image.jpg",
                    mimeType: "image/jpeg"
                )
            }
            return
        }

        if payload.url != nil {
            do {
                let localURL = try await ensureLocalFile(for: payload, reason: "gallery.preview")
                await MainActor.run {
                    let name = payload.url?.lastPathComponent.removingPercentEncoding ?? "image"
                    binding.wrappedValue = FilePreviewInput(
                        fileURL: localURL,
                        displayName: name,
                        mimeType: FileUtilities.mimeType(forName: name)
                    )
                }
            } catch {
                await MainActor.run {
                    binding.wrappedValue = Self.previewUnavailableInput()
                }
            }
            return
        }

        await MainActor.run {
            binding.wrappedValue = Self.previewUnavailableInput()
        }
    }

    @MainActor
    private func ensureLocalFile(for payload: ChatImagePayload, reason: String) async throws -> URL {
        if let existing = downloadedImageFiles[payload.id] {
            ChatAttachmentImageDiagnostics.debug(
                "gallery.ensureLocal.skipAlreadyLoaded payloadID=\(payload.id.uuidString.prefix(8)) reason=\(reason)"
            )
            return existing
        }
        guard let managedFile = payload.managedFile else {
            throw URLError(.unsupportedURL)
        }
        guard downloadingImageIDs.contains(payload.id) == false else {
            throw URLError(.cannotLoadFromNetwork)
        }
        downloadingImageIDs.insert(payload.id)
        defer { downloadingImageIDs.remove(payload.id) }

        ChatAttachmentImageDiagnostics.debug(
            "gallery.ensureLocal.start reason=\(reason) id=\(payload.id.uuidString.prefix(8)) url=\(managedFile.filePath)"
        )
        do {
            if let cachedURL = await fileTransferService.cachedURL(file: managedFile) {
                downloadedImageFiles[payload.id] = cachedURL
                failedImageIDs.remove(payload.id)
                ChatAttachmentImageDiagnostics.info(
                    "gallery.ensureLocal.cacheHit payloadID=\(payload.id.uuidString.prefix(8)) path=\(cachedURL.path)"
                )
                return cachedURL
            }
            let localURL = try await fileTransferService.download(file: managedFile)
            downloadedImageFiles[payload.id] = localURL
            failedImageIDs.remove(payload.id)
            ChatAttachmentImageDiagnostics.info(
                "gallery.ensureLocal.ok payloadID=\(payload.id.uuidString.prefix(8)) path=\(localURL.path)"
            )
            return localURL
        } catch {
            ChatAttachmentImageDiagnostics.warning(
                "gallery.ensureLocal.fail payloadID=\(payload.id.uuidString.prefix(8)) error=\(ChatAttachmentImageDiagnostics.errorDescription(error))"
            )
            throw error
        }
    }

    @MainActor
    private func loadImageIfNeeded(for payload: ChatImagePayload, reason: String) async {
        if payload.image != nil {
            ChatAttachmentImageDiagnostics.debug(
                "gallery.load.skipInlineImage payloadID=\(payload.id.uuidString.prefix(8))"
            )
            return
        }
        if downloadedImageFiles[payload.id] != nil {
            return
        }
        if let managedFile = payload.managedFile,
           let cachedURL = await fileTransferService.cachedURL(file: managedFile) {
            await MainActor.run {
                downloadedImageFiles[payload.id] = cachedURL
                failedImageIDs.remove(payload.id)
            }
            ChatAttachmentImageDiagnostics.info(
                "gallery.load.localCacheHit payloadID=\(payload.id.uuidString.prefix(8)) path=\(cachedURL.path)"
            )
            return
        }
        guard payload.url != nil else {
            ChatAttachmentImageDiagnostics.debug(
                "gallery.load.skipNoURL payloadID=\(payload.id.uuidString.prefix(8))"
            )
            return
        }
        guard downloadingImageIDs.contains(payload.id) == false else { return }
        guard autoTriggeredImageIDs.contains(payload.id) == false else { return }

        await MainActor.run {
            autoTriggeredImageIDs.insert(payload.id)
            failedImageIDs.remove(payload.id)
        }

        do {
            _ = try await ensureLocalFile(for: payload, reason: reason)
        } catch {
            await MainActor.run {
                failedImageIDs.insert(payload.id)
            }
        }
    }

    private static func previewUnavailableInput() -> FilePreviewInput {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-preview-missing-\(UUID().uuidString)")
        return FilePreviewInput(fileURL: url, displayName: "Preview unavailable", mimeType: nil)
    }

    private static func writeTempJPEG(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-preview-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private static func writeTempData(_ data: Data, suffix: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-preview-\(UUID().uuidString).\(suffix)")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}

private struct ChatUIKitMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let locations: [ChatMapLocationPayload]
    let mapType: MKMapType

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsCompass = true
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = mapType
        mapView.setRegion(region, animated: true)
        mapView.removeAnnotations(mapView.annotations)
        let annotations = locations.map { location -> MKPointAnnotation in
            let a = MKPointAnnotation()
            a.title = location.name
            a.coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            return a
        }
        mapView.addAnnotations(annotations)
    }
}

private struct ChatHTMLWebView: UIViewRepresentable {
    let htmlContent: String

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(htmlContent, baseURL: nil)
    }
}
