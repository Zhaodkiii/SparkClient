import AVFoundation
import SwiftUI
import UIKit

private enum CaseDocumentCameraSheet: Identifiable {
    case guide(isFirstLaunch: Bool)

    var id: String {
        switch self {
        case .guide(let isFirstLaunch):
            return "guide:\(isFirstLaunch)"
        }
    }
}

/// 病例档案连续拍摄自定义相机（横向滚动预览，无固定槽位）。
struct CaseDocumentCameraSceneView: View {
    let maxCaptureCount: Int
    let onCancel: () -> Void
    let onImagesCaptured: ([CaseDocumentCapturedImage]) -> Void

    @State private var cameraManager = CustomCameraManager(
        captureSession: AVCaptureSession(),
        captureDeviceInputType: AVCaptureDeviceInput.self
    )
    @State private var presentedSheet: CaseDocumentCameraSheet?
    @State private var capturedImages: [CaseDocumentCapturedImage] = []
    @State private var alertMessage: String?
    @State private var previewInput: FilePreviewInput?
    @State private var previewTempFileURL: URL?

    init(
        maxCaptureCount: Int,
        onCancel: @escaping () -> Void,
        onImagesCaptured: @escaping ([CaseDocumentCapturedImage]) -> Void
    ) {
        self.maxCaptureCount = max(1, maxCaptureCount)
        self.onCancel = onCancel
        self.onImagesCaptured = onImagesCaptured
        if !CaseDocumentCameraGuideStore.shared.hasSeenGuide {
            _presentedSheet = State(initialValue: .guide(isFirstLaunch: true))
        }
    }

    private var canFinish: Bool {
        capturedImages.isEmpty == false
    }

    private var canCaptureMore: Bool {
        capturedImages.count < maxCaptureCount
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            CustomCameraView(manager: cameraManager)
                .setCameraOutputType(.photo)
                .setCameraPosition(.back)
                .setAudioAvailability(false)
                .setGridVisibility(false)
                .setLightMode(.off)
                .setCapturedMediaScreen(DefaultCustomCapturedMediaScreen.init)
                .setCameraScreen { cameraManager, namespace, closeAction in
                    CaseDocumentCameraScreen(
                        cameraManager: cameraManager,
                        namespace: namespace,
                        closeCustomCameraAction: closeAction,
                        maxCaptureCount: maxCaptureCount,
                        onCancel: onCancel,
                        onShowGuide: { presentedSheet = .guide(isFirstLaunch: false) },
                        onFinish: finishCapture,
                        onPreview: previewImage,
                        onDelete: deleteImage,
                        onCaptureLimitReached: showCaptureLimitMessage,
                        canFinish: canFinish,
                        canCaptureMore: canCaptureMore,
                        capturedImages: $capturedImages
                    )
                }
                .setCloseCustomCameraAction(onCancel)
                .onImageCaptured { image, _ in
                    handleConfirmedCapture(image)
                }
                .startSession()
                .ignoresSafeArea()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .guide(let isFirstLaunch):
                CaseDocumentCameraGuideView(maxCaptureCount: maxCaptureCount) {
                    dismissGuide(isFirstLaunch: isFirstLaunch)
                }
                .interactiveDismissDisabled()
            }
        }
        .sheet(item: $previewInput) { input in
            QuickLookPreviewBridge(inputs: [input], startIndex: 0)
                .onDisappear {
                    cleanupPreviewTempFile()
                }
        }
        .alert(
            alertMessage ?? "",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        alertMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.text("common.got_it", fallback: "知道了"), role: .cancel) {}
        }
    }
}

private extension CaseDocumentCameraSceneView {
    func dismissGuide(isFirstLaunch: Bool) {
        if isFirstLaunch {
            CaseDocumentCameraGuideStore.shared.markAsSeen()
        }
        presentedSheet = nil
    }

    func handleConfirmedCapture(_ image: UIImage) {
        guard canCaptureMore else {
            showCaptureLimitMessage()
            cameraManager.setCapturedMedia(nil)
            return
        }

        let nextIndex = capturedImages.count + 1
        capturedImages.append(CaseDocumentCapturedImage(index: nextIndex, image: image))
        cameraManager.setCapturedMedia(nil)

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CaseDocumentCameraSceneView: page=\(nextIndex) captured total=\(capturedImages.count)"
        )
    }

    func finishCapture() {
        guard canFinish else {
            alertMessage = L10n.text(
                "home.medical.case_document.camera.validation.empty",
                fallback: "请先拍摄病历图片"
            )
            return
        }
        onImagesCaptured(capturedImages)
    }

    func showCaptureLimitMessage() {
        alertMessage = L10n.text(
            "home.medical.case_document.camera.validation.limit",
            fallback: "已达到本次拍摄上限"
        )
    }

    func previewImage(_ item: CaseDocumentCapturedImage) {
        cleanupPreviewTempFile()

        guard let data = item.image.jpegData(compressionQuality: 0.95) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("case_document_preview_\(item.index)_\(UUID().uuidString).jpg")

        do {
            try data.write(to: url, options: .atomic)
            previewTempFileURL = url
            previewInput = FilePreviewInput(
                fileURL: url,
                displayName: String(
                    format: L10n.text(
                        "home.medical.case_document.camera.preview.page",
                        fallback: "第 %d 张"
                    ),
                    locale: Locale.current,
                    item.index
                )
            )
        } catch {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "CaseDocumentCameraSceneView: preview temp file write failed page=\(item.index)"
            )
        }
    }

    func deleteImage(_ item: CaseDocumentCapturedImage) {
        capturedImages.removeAll { $0.id == item.id }
        capturedImages = capturedImages.enumerated().map { offset, image in
            CaseDocumentCapturedImage(id: image.id, index: offset + 1, image: image.image)
        }
    }

    func cleanupPreviewTempFile() {
        if let previewTempFileURL {
            try? FileManager.default.removeItem(at: previewTempFileURL)
        }
        previewTempFileURL = nil
    }
}

// MARK: - 底部面板尺寸

private struct CaseDocumentBottomPanelMetrics {
    let panelHeight: CGFloat

    var topPadding: CGFloat { clamp(panelHeight * 0.08, min: 12, max: 18) }
    var rowSpacing: CGFloat { clamp(panelHeight * 0.10, min: 14, max: 20) }
    var thumbnailHeight: CGFloat { clamp(panelHeight * 0.36, min: 72, max: 92) }
    var thumbnailWidth: CGFloat { thumbnailHeight * 0.72 }
    var thumbnailCornerRadius: CGFloat { clamp(thumbnailHeight * 0.11, min: 8, max: 10) }
    var thumbnailSpacing: CGFloat { 10 }
    var captureButtonOuter: CGFloat { clamp(panelHeight * 0.33, min: 72, max: 84) }
    var captureButtonInner: CGFloat { captureButtonOuter * 0.81 }
    var captureStrokeWidth: CGFloat { 5 }
    var captureIconSize: CGFloat { captureButtonInner * 0.38 }
    var sideActionWidth: CGFloat { clamp(panelHeight * 0.83, min: 72, max: 188) }
    var titleIconSize: CGFloat { clamp(panelHeight * 0.07, min: 16, max: 18) }
    var finishHorizontalPadding: CGFloat { 18 }
    var finishVerticalPadding: CGFloat { 10 }
    var finishCornerRadius: CGFloat { 12 }
    var deleteButtonSize: CGFloat { clamp(thumbnailHeight * 0.30, min: 22, max: 28) }
    var deleteIconSize: CGFloat { deleteButtonSize * 0.40 }
    var deleteButtonOffset: CGFloat { deleteButtonSize * 0.20 }
    var pageBadgeSize: CGFloat { clamp(thumbnailHeight * 0.28, min: 20, max: 24) }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(maxValue, Swift.max(minValue, value))
    }
}

// MARK: - 取景器布局

private struct CaseDocumentViewfinderLayout {
    let viewfinderRect: CGRect
    let bottomPanelHeight: CGFloat
    let promptY: CGFloat

    init(proxy: GeometryProxy) {
        let availableWidth = proxy.size.width
        let availableHeight = proxy.size.height
        let safeTop = proxy.safeAreaInsets.top
        let safeBottom = proxy.safeAreaInsets.bottom

        let bottomPanelHeight = min(max(196, availableHeight * 0.24), 252)
        let topToolbarHeight = safeTop + 58
        let promptHeight: CGFloat = 48
        let topVerticalGap: CGFloat = 22
        let bottomVerticalGap: CGFloat = 10
        let viewfinderPromptGap: CGFloat = 10

        let cameraAreaTop = topToolbarHeight + topVerticalGap
        let cameraAreaBottom = availableHeight - safeBottom - bottomPanelHeight - promptHeight - bottomVerticalGap
        let cameraAreaHeight = max(260, cameraAreaBottom - cameraAreaTop)

        let targetAspect: CGFloat = 1.414
        let maxWidth = min(availableWidth * 0.88, 400)
        let maxHeight = cameraAreaHeight * 0.86
        let widthByHeight = maxHeight / targetAspect

        let viewfinderWidth = min(maxWidth, widthByHeight)
        let viewfinderHeight = min(maxHeight, viewfinderWidth * targetAspect)
        let viewfinderCenterY = cameraAreaTop + cameraAreaHeight * 0.54

        self.bottomPanelHeight = bottomPanelHeight
        self.viewfinderRect = CGRect(
            x: (availableWidth - viewfinderWidth) / 2,
            y: viewfinderCenterY - viewfinderHeight / 2,
            width: viewfinderWidth,
            height: viewfinderHeight
        )
        self.promptY = min(
            viewfinderRect.maxY + viewfinderPromptGap + promptHeight / 2,
            availableHeight - safeBottom - bottomPanelHeight - bottomVerticalGap - promptHeight / 2
        )
    }
}

// MARK: - 相机屏幕

private struct CaseDocumentCameraScreen: CustomCameraScreen {
    @ObservedObject var cameraManager: CustomCameraManager
    let namespace: Namespace.ID
    let closeCustomCameraAction: () -> Void
    let maxCaptureCount: Int
    let onCancel: () -> Void
    let onShowGuide: () -> Void
    let onFinish: () -> Void
    let onPreview: (CaseDocumentCapturedImage) -> Void
    let onDelete: (CaseDocumentCapturedImage) -> Void
    let onCaptureLimitReached: () -> Void
    let canFinish: Bool
    let canCaptureMore: Bool
    @Binding var capturedImages: [CaseDocumentCapturedImage]

    @State private var isCapturing = false

    private let accentColor = Color(uiColor: .systemBlue)
    private var navigationTitle: String {
        L10n.text("home.medical.case_document.camera.title", fallback: "病历")
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = CaseDocumentViewfinderLayout(proxy: proxy)
            let safeBottom = proxy.safeAreaInsets.bottom

            ZStack {
                createCameraOutputView()
                    .ignoresSafeArea()

                CaseDocumentCameraOutsideMask(
                    cutoutRect: layout.viewfinderRect,
                    cornerRadius: min(layout.viewfinderRect.width, layout.viewfinderRect.height) * 0.06
                )
                .fill(
                    Color.black.opacity(0.38),
                    style: FillStyle(eoFill: true)
                )
                .ignoresSafeArea()

                ExaminationReportCameraViewfinderShape()
                    .stroke(
                        Color.white,
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(
                        width: layout.viewfinderRect.width,
                        height: layout.viewfinderRect.height
                    )
                    .cameraCaptureViewfinder()
                    .position(
                        x: layout.viewfinderRect.midX,
                        y: layout.viewfinderRect.midY
                    )

                promptText
                    .position(x: proxy.size.width / 2, y: layout.promptY)

                bottomPanel(
                    safeBottom: safeBottom,
                    width: proxy.size.width,
                    panelHeight: layout.bottomPanelHeight
                )
            }
            .bindCameraCaptureViewfinder(to: cameraManager)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(.title2, design: .default).weight(.medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
            }

            ToolbarItem(placement: .principal) {
                Text(navigationTitle)
                    .font(.system(.largeTitle, design: .default).weight(.heavy))
                    .foregroundColor(.white)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onShowGuide) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(.title3, design: .default).weight(.medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .statusBarHidden(false)
    }
}

private extension CaseDocumentCameraScreen {
    var promptText: some View {
        Group {
            if capturedImages.isEmpty {
                Text(
                    L10n.text(
                        "home.medical.case_document.camera.prompt.default",
                        fallback: "保持病历四边完整入框，文字清晰无遮挡"
                    )
                )
            } else {
                Text(
                    String(
                        format: L10n.text(
                            "home.medical.case_document.camera.prompt.page",
                            fallback: "第 %d 张 · 保持病历四边完整入框"
                        ),
                        locale: Locale.current,
                        capturedImages.count + 1
                    )
                )
            }
        }
        .font(.system(.headline, design: .default).weight(.bold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 32)
        .animation(.easeInOut(duration: 0.2), value: capturedImages.count)
    }

    func bottomPanel(safeBottom: CGFloat, width: CGFloat, panelHeight: CGFloat) -> some View {
        let metrics = CaseDocumentBottomPanelMetrics(panelHeight: panelHeight)

        return VStack(spacing: metrics.rowSpacing) {
            thumbnailScrollRow(metrics: metrics)

            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: metrics.titleIconSize, weight: .semibold))
                        .foregroundColor(accentColor)

                    Text(navigationTitle)
                        .font(.system(.title3, design: .default).weight(.bold))
                        .foregroundColor(Color(uiColor: .label))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: metrics.sideActionWidth)

                Spacer(minLength: 0)

                Button(action: capturePhoto) {
                    ZStack {
                        Circle()
                            .stroke(accentColor.opacity(0.35), lineWidth: metrics.captureStrokeWidth)
                            .frame(width: metrics.captureButtonOuter, height: metrics.captureButtonOuter)

                        Circle()
                            .fill(accentColor)
                            .frame(width: metrics.captureButtonInner, height: metrics.captureButtonInner)

                        Image(systemName: "camera.fill")
                            .font(.system(size: metrics.captureIconSize, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCapturing || !canCaptureMore)
                .opacity(isCapturing || !canCaptureMore ? 0.55 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCapturing)

                Spacer(minLength: 0)

                Button(action: onFinish) {
                    Text(L10n.text("common.done", fallback: "完成"))
                        .font(.system(.headline, design: .default).weight(.semibold))
                        .foregroundColor(
                            canFinish
                                ? Color(uiColor: .systemBackground)
                                : Color(uiColor: .tertiaryLabel)
                        )
                        .padding(.horizontal, metrics.finishHorizontalPadding)
                        .padding(.vertical, metrics.finishVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: metrics.finishCornerRadius, style: .continuous)
                                .fill(
                                    canFinish
                                        ? accentColor
                                        : Color(uiColor: .secondarySystemBackground)
                                )
                        )
                }
                .buttonStyle(.plain)
                .frame(width: metrics.sideActionWidth)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, max(safeBottom, 16))
        }
        .frame(width: width, height: panelHeight + safeBottom, alignment: .top)
        .padding(.top, metrics.topPadding)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .ignoresSafeArea(edges: .bottom)
        )
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    func thumbnailScrollRow(metrics: CaseDocumentBottomPanelMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: metrics.thumbnailSpacing) {
                if capturedImages.isEmpty {
                    emptyThumbnailPlaceholder(metrics: metrics)
                } else {
                    ForEach(capturedImages) { item in
                        thumbnailItem(for: item, metrics: metrics)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: metrics.thumbnailHeight + 4)
    }

    func emptyThumbnailPlaceholder(metrics: CaseDocumentBottomPanelMetrics) -> some View {
        RoundedRectangle(cornerRadius: metrics.thumbnailCornerRadius, style: .continuous)
            .stroke(Color(uiColor: .separator).opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .frame(width: metrics.thumbnailWidth, height: metrics.thumbnailHeight)
            .overlay {
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: metrics.thumbnailHeight * 0.28, weight: .medium))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
    }

    func thumbnailItem(
        for item: CaseDocumentCapturedImage,
        metrics: CaseDocumentBottomPanelMetrics
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onPreview(item)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: metrics.thumbnailWidth, height: metrics.thumbnailHeight)
                        .clipShape(
                            RoundedRectangle(cornerRadius: metrics.thumbnailCornerRadius, style: .continuous)
                        )

                    Text("\(item.index)")
                        .font(.system(size: metrics.pageBadgeSize * 0.55, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: metrics.pageBadgeSize, height: metrics.pageBadgeSize)
                        .background(Circle().fill(accentColor))
                        .padding(6)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.thumbnailCornerRadius, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                onDelete(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: metrics.deleteIconSize, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: metrics.deleteButtonSize, height: metrics.deleteButtonSize)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .offset(x: metrics.deleteButtonOffset, y: -metrics.deleteButtonOffset)
        }
    }

    func capturePhoto() {
        guard !isCapturing else { return }
        guard canCaptureMore else {
            onCaptureLimitReached()
            return
        }

        isCapturing = true
        setOutputType(.photo)
        captureOutput()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isCapturing = false
        }
    }
}

private struct CaseDocumentCameraOutsideMask: Shape {
    let cutoutRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: cutoutRect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}
