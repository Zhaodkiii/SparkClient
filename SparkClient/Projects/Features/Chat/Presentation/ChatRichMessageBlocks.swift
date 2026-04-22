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

struct ChatSleepCardView: View {
    let model: ChatHealthSleepModel

    private var sortedDays: [ChatHealthSleepModel.Day] {
        model.days.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("睡眠")
                .font(.subheadline.weight(.semibold))

            ForEach(sortedDays) { day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(day.date)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(day.summary.totalSleepMinutes) 分钟")
                            .font(.caption.weight(.semibold))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                            HStack(spacing: 2) {
                                ForEach(day.timeline) { segment in
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(chatSleepStageColor(segment.stage))
                                        .frame(width: max(2, geo.size.width * max(0, segment.widthPercent)))
                                }
                            }
                        }
                    }
                    .frame(height: 12)

                    HStack(spacing: 10) {
                        stageChip(.deep, value: day.stages.deep)
                        stageChip(.core, value: day.stages.core)
                        stageChip(.rem, value: day.stages.rem)
                        if day.stages.awake > 0 {
                            stageChip(.awake, value: day.stages.awake)
                        }
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

    private func stageChip(_ stage: ChatHealthSleepModel.Stage, value: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(chatSleepStageColor(stage))
                .frame(width: 7, height: 7)
            Text("\(stage.displayName) \(value)m")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private func chatSleepStageColor(_ stage: ChatHealthSleepModel.Stage) -> Color {
    switch stage {
    case .deep:
        return Color(red: 30 / 255, green: 58 / 255, blue: 138 / 255)
    case .core:
        return Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    case .rem:
        return Color(red: 96 / 255, green: 165 / 255, blue: 250 / 255)
    case .awake:
        return Color(red: 255 / 255, green: 107 / 255, blue: 107 / 255)
    case .unspecified:
        return Color(red: 95 / 255, green: 85 / 255, blue: 236 / 255)
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
        for attachment in message.attachments where attachment.isChatImageLike {
            if attachment.url == nil,
               let raw = attachment.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               raw.isEmpty == false {
                if let image = decodeImage(from: raw) {
                    payloads.append(ChatImagePayload(id: attachment.id, url: nil, image: image, downloadableAttachment: nil))
                    continue
                }
                if let link = inferHTTPSURLString(from: raw),
                   let u = URL(string: link),
                   let scheme = u.scheme?.lowercased(),
                   scheme == "http" || scheme == "https" {
                    let resolved = attachment.replacing(url: u)
                    payloads.append(
                        ChatImagePayload(id: attachment.id, url: u, image: nil, downloadableAttachment: resolved)
                    )
                    continue
                }
            }

            if let parsed = attachment.sparkClientOSSFileUUIDAndFileName(),
               let img = ChatLocalImageCache.uiImageIfCached(fileUUID: parsed.fileUUID, originalName: parsed.fileName) {
                payloads.append(ChatImagePayload(id: attachment.id, url: nil, image: img, downloadableAttachment: nil))
                continue
            }
            guard let downloadURL = attachment.effectiveHTTPSImageDownloadURL else { continue }
            payloads.append(
                ChatImagePayload(
                    id: attachment.id,
                    url: downloadURL,
                    image: nil,
                    downloadableAttachment: attachment
                )
            )
        }
        return payloads
    }

    /// 从长文本中截取首个 http(s) URL 子串，避免对整段 OCR 调用 `URL(string:)`。
    private static func inferHTTPSURLString(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        if trimmed.count <= 2048,
           let u = URL(string: trimmed),
           let scheme = u.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return trimmed
        }
        let markers = ["https://", "http://"]
        var bestStart: String.Index?
        for marker in markers {
            if let r = trimmed.range(of: marker, options: [.caseInsensitive]) {
                if bestStart == nil || r.lowerBound < bestStart! {
                    bestStart = r.lowerBound
                }
            }
        }
        guard let start = bestStart else { return nil }
        var end = start
        let limit = trimmed.index(start, offsetBy: 2048, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
        while end < limit {
            let ch = trimmed[end]
            if ch.isWhitespace || ch == "\"" || ch == "'" || ch == "’" || ch == ")" || ch == "]" || ch == "}" || ch == "<" {
                break
            }
            end = trimmed.index(after: end)
        }
        let slice = String(trimmed[start ..< end])
        return slice.isEmpty ? nil : slice
    }

    private static func decodeImage(from text: String) -> UIImage? {
        if text.hasPrefix("data:image"),
           let base64 = text.components(separatedBy: ",").last,
           let data = Data(base64Encoded: base64) {
            return UIImage(data: data)
        }
        if let data = Data(base64Encoded: text) {
            return UIImage(data: data)
        }
        return nil
    }
}

struct ChatImagePayload: Identifiable, Equatable {
    let id: UUID
    let url: URL?
    let image: UIImage?
    /// 需经 `downloadChatImageToLocalFile` 落盘到 `SparkClient.FileCache` 的附件（同步图片、远程 https 图）。
    let downloadableAttachment: ChatAttachment?
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
    var style: ChatImageGalleryStyle = .user
    var unifiedFilePreview: Binding<FilePreviewInput?>?
    var downloadToLocalFile: ((ChatAttachment) async throws -> URL)? = nil
    @State private var downloadingImageIDs: Set<UUID> = []
    @State private var downloadedImageFiles: [UUID: URL] = [:]
    @State private var autoTriggeredImageIDs: Set<UUID> = []
    @State private var failedImageIDs: Set<UUID> = []

    init(
        images: [ChatImagePayload],
        style: ChatImageGalleryStyle = .user,
        unifiedFilePreview: Binding<FilePreviewInput?>? = nil,
        downloadToLocalFile: ((ChatAttachment) async throws -> URL)? = nil
    ) {
        self.images = images
        self.style = style
        self.unifiedFilePreview = unifiedFilePreview
        self.downloadToLocalFile = downloadToLocalFile
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
    }

    @ViewBuilder
    private func galleryCell(for payload: ChatImagePayload) -> some View {
        ZStack {
            if let local = downloadedImageFiles[payload.id], let image = UIImage(contentsOfFile: local.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let image = payload.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if payload.downloadableAttachment != nil {
                downloadPlaceholder(for: payload)
            } else if let url = payload.url {
                // 理论上图片附件均走 `downloadableAttachment` + 本地缓存；此处仅兜底非 http(s) 等异常 URL。
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
        .frame(width: style.thumbSide, height: style.thumbSide)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .contextMenu {
            contextButtons(for: payload)
        }
        .onTapGesture {
            Task {
                await openPreview(for: payload)
            }
        }
        .task(id: payload.id) {
            await autoDownloadIfNeeded(for: payload)
        }
    }

    @ViewBuilder
    private func downloadPlaceholder(for payload: ChatImagePayload) -> some View {
        let failed = failedImageIDs.contains(payload.id)
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
            if failed, let attachment = payload.downloadableAttachment {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            await MainActor.run {
                                failedImageIDs.remove(payload.id)
                                autoTriggeredImageIDs.remove(payload.id)
                            }
                            do {
                                _ = try await ensureLocalFile(for: payload.id, attachment: attachment)
                            } catch {
                                await MainActor.run {
                                    failedImageIDs.insert(payload.id)
                                }
                            }
                        }
                    } label: {
                        Label(L10n.text("common.retry"), systemImage: "arrow.clockwise.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            } else {
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
        if let attachment = payload.downloadableAttachment {
            do {
                let local = try await ensureLocalFile(for: payload.id, attachment: attachment)
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
        if let attachment = payload.downloadableAttachment {
            do {
                let local = try await ensureLocalFile(for: payload.id, attachment: attachment)
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

        if let attachment = payload.downloadableAttachment {
            do {
                let localURL = try await ensureLocalFile(for: payload.id, attachment: attachment)
                await MainActor.run {
                    let name = attachment.url?.lastPathComponent.removingPercentEncoding ?? "image"
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

    private func ensureLocalFile(for payloadID: UUID, attachment: ChatAttachment) async throws -> URL {
        if let existing = downloadedImageFiles[payloadID] {
            return existing
        }
        guard let downloader = downloadToLocalFile else {
            throw URLError(.unsupportedURL)
        }
        await MainActor.run {
            downloadingImageIDs.insert(payloadID)
        }
        defer {
            Task { @MainActor in
                downloadingImageIDs.remove(payloadID)
            }
        }
        let localURL = try await downloader(attachment)
        await MainActor.run {
            downloadedImageFiles[payloadID] = localURL
            failedImageIDs.remove(payloadID)
        }
        return localURL
    }

    private func autoDownloadIfNeeded(for payload: ChatImagePayload) async {
        guard let attachment = payload.downloadableAttachment else { return }
        guard downloadedImageFiles[payload.id] == nil else { return }
        guard downloadingImageIDs.contains(payload.id) == false else { return }
        guard autoTriggeredImageIDs.contains(payload.id) == false else { return }
        await MainActor.run {
            autoTriggeredImageIDs.insert(payload.id)
        }
        do {
            _ = try await ensureLocalFile(for: payload.id, attachment: attachment)
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
