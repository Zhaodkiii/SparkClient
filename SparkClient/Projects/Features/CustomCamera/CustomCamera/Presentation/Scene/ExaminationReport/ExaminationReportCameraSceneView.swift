import AVFoundation
import SwiftUI
import UIKit

/// 医疗报告相机业务上下文（检查报告 / 体检报告共用拍摄页）。
enum ExaminationReportCameraContext {
    case examinationReport
    case healthExamReport

    var navigationTitle: String {
        switch self {
        case .examinationReport:
            return L10n.text("home.medical.examination_report.camera.title", fallback: "检查报告")
        case .healthExamReport:
            return L10n.text("home.medical.health_exam_report.camera.title", fallback: "体检报告")
        }
    }

    var guideTitle: String {
        switch self {
        case .examinationReport:
            return L10n.text(
                "home.medical.examination_report.camera.guide.title",
                fallback: "检查报告拍摄"
            )
        case .healthExamReport:
            return L10n.text(
                "home.medical.health_exam_report.camera.guide.title",
                fallback: "体检报告拍摄"
            )
        }
    }

    var guideSubtitle: String {
        switch self {
        case .examinationReport:
            return L10n.text(
                "home.medical.examination_report.camera.guide.subtitle",
                fallback: "将报告平放，保持四边完整入框，文字清晰无遮挡。"
            )
        case .healthExamReport:
            return L10n.text(
                "home.medical.health_exam_report.camera.guide.subtitle",
                fallback: "体检报告页数较多，可按顺序连续拍摄，保持每页清晰完整。"
            )
        }
    }
}

private enum ExaminationReportCameraSheet: Identifiable {
    case guide(isFirstLaunch: Bool)

    var id: String {
        switch self {
        case .guide(let isFirstLaunch):
            return "guide:\(isFirstLaunch)"
        }
    }
}

/// 检查/体检报告连续拍摄自定义相机（横向滚动预览，无固定槽位）。
struct ExaminationReportCameraSceneView: View {
    let context: ExaminationReportCameraContext
    let maxCaptureCount: Int
    let onCancel: () -> Void
    let onImagesCaptured: ([ExaminationReportCapturedImage]) -> Void

    @State private var cameraManager = CustomCameraManager(
        captureSession: AVCaptureSession(),
        captureDeviceInputType: AVCaptureDeviceInput.self
    )
    @State private var presentedSheet: ExaminationReportCameraSheet?
    @State private var capturedImages: [ExaminationReportCapturedImage] = []
    @State private var alertMessage: String?
    @State private var previewInput: FilePreviewInput?
    @State private var previewTempFileURL: URL?

    init(
        context: ExaminationReportCameraContext,
        maxCaptureCount: Int,
        onCancel: @escaping () -> Void,
        onImagesCaptured: @escaping ([ExaminationReportCapturedImage]) -> Void
    ) {
        self.context = context
        self.maxCaptureCount = max(1, maxCaptureCount)
        self.onCancel = onCancel
        self.onImagesCaptured = onImagesCaptured
        if !ExaminationReportCameraGuideStore.shared.hasSeenGuide {
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
                    ExaminationReportCameraScreen(
                        cameraManager: cameraManager,
                        namespace: namespace,
                        closeCustomCameraAction: closeAction,
                        context: context,
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
                // CAMERA-000005：拍摄页取消根级忽略安全区，布局按安全区内坐标系计算。
                .startSession()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .guide(let isFirstLaunch):
                ExaminationReportCameraGuideView(
                    context: context,
                    maxCaptureCount: maxCaptureCount
                ) {
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

private extension ExaminationReportCameraSceneView {
    func dismissGuide(isFirstLaunch: Bool) {
        if isFirstLaunch {
            ExaminationReportCameraGuideStore.shared.markAsSeen()
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
        capturedImages.append(ExaminationReportCapturedImage(index: nextIndex, image: image))
        cameraManager.setCapturedMedia(nil)

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "ExaminationReportCameraSceneView: page=\(nextIndex) captured total=\(capturedImages.count)"
        )
    }

    func finishCapture() {
        guard canFinish else {
            alertMessage = L10n.text(
                "home.medical.examination_report.camera.validation.empty",
                fallback: "请先拍摄报告图片"
            )
            return
        }
        onImagesCaptured(capturedImages)
    }

    func showCaptureLimitMessage() {
        alertMessage = L10n.text(
            "home.medical.examination_report.camera.validation.limit",
            fallback: "已达到本次拍摄上限"
        )
    }

    func previewImage(_ item: ExaminationReportCapturedImage) {
        cleanupPreviewTempFile()

        guard let data = item.image.jpegData(compressionQuality: 0.95) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("examination_report_preview_\(item.index)_\(UUID().uuidString).jpg")

        do {
            try data.write(to: url, options: .atomic)
            previewTempFileURL = url
            previewInput = FilePreviewInput(
                fileURL: url,
                displayName: String(
                    format: L10n.text(
                        "home.medical.examination_report.camera.preview.page",
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
                message: "ExaminationReportCameraSceneView: preview temp file write failed page=\(item.index)"
            )
        }
    }

    func deleteImage(_ item: ExaminationReportCapturedImage) {
        capturedImages.removeAll { $0.id == item.id }
        capturedImages = capturedImages.enumerated().map { offset, image in
            ExaminationReportCapturedImage(id: image.id, index: offset + 1, image: image.image)
        }
    }

    func cleanupPreviewTempFile() {
        if let previewTempFileURL {
            try? FileManager.default.removeItem(at: previewTempFileURL)
        }
        previewTempFileURL = nil
    }
}

// MARK: - 底部面板尺寸（限定在合理区间，避免随屏幕线性放大）

private struct ExaminationReportBottomPanelMetrics {
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

// MARK: - 取景器布局（A4 竖版友好比例）
// CAMERA-000005：GeometryReader 已在安全区内，不再重复扣除 safeTop/safeBottom。

private struct ExaminationReportViewfinderLayout {
    let viewfinderRect: CGRect
    let bottomPanelHeight: CGFloat
    let promptY: CGFloat

    init(proxy: GeometryProxy) {
        let availableWidth = proxy.size.width
        let contentBottom = proxy.size.height

        let bottomPanelHeight = min(max(196, contentBottom * 0.24), 252)
        let promptHeight: CGFloat = 48
        let topVerticalGap: CGFloat = 12
        let bottomVerticalGap: CGFloat = 10
        let viewfinderPromptGap: CGFloat = 10

        // GeometryReader 的内容区已经位于导航栏下方，不再重复预留工具栏高度。
        let cameraAreaTop = topVerticalGap
        let bottomPanelTop = contentBottom - bottomPanelHeight
        let promptBottomLimit = bottomPanelTop - bottomVerticalGap
        let cameraAreaBottom = promptBottomLimit - promptHeight
        let cameraAreaHeight = max(0, cameraAreaBottom - cameraAreaTop)

        // 报告拍摄优先占满横向空间；高度不足时在舒适竖版比例内自适应。
        let preferredWidth = min(max(0, availableWidth - 32), 440)
        let availableAspect = preferredWidth > 0 ? cameraAreaHeight / preferredWidth : 1.414
        let viewfinderAspect = min(1.414, max(1.28, availableAspect))
        let viewfinderHeight = min(cameraAreaHeight, preferredWidth * viewfinderAspect)
        let viewfinderWidth = min(preferredWidth, viewfinderHeight / viewfinderAspect)
        let remainingVerticalSpace = max(0, cameraAreaHeight - viewfinderHeight)
        let viewfinderTop = cameraAreaTop + remainingVerticalSpace * 0.35

        self.bottomPanelHeight = bottomPanelHeight
        self.viewfinderRect = CGRect(
            x: (availableWidth - viewfinderWidth) / 2,
            y: viewfinderTop,
            width: viewfinderWidth,
            height: viewfinderHeight
        )

        let idealPromptY = viewfinderRect.maxY + viewfinderPromptGap + promptHeight / 2
        let maxPromptY = promptBottomLimit - promptHeight / 2
        self.promptY = min(idealPromptY, maxPromptY)
    }
}

// MARK: - 相机屏幕

private struct ExaminationReportCameraScreen: CustomCameraScreen {
    @ObservedObject var cameraManager: CustomCameraManager
    let namespace: Namespace.ID
    let closeCustomCameraAction: () -> Void
    let context: ExaminationReportCameraContext
    let maxCaptureCount: Int
    let onCancel: () -> Void
    let onShowGuide: () -> Void
    let onFinish: () -> Void
    let onPreview: (ExaminationReportCapturedImage) -> Void
    let onDelete: (ExaminationReportCapturedImage) -> Void
    let onCaptureLimitReached: () -> Void
    let canFinish: Bool
    let canCaptureMore: Bool
    @Binding var capturedImages: [ExaminationReportCapturedImage]

    @State private var isCapturing = false

    private let accentColor = Color(uiColor: .systemBlue)

    var body: some View {
        GeometryReader { proxy in
            let layout = ExaminationReportViewfinderLayout(proxy: proxy)

            ZStack {
                createCameraOutputView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                ExaminationReportCameraOutsideMask(
                    cutoutRect: layout.viewfinderRect,
                    cornerRadius: min(layout.viewfinderRect.width, layout.viewfinderRect.height) * 0.06
                )
                .fill(
                    Color.black.opacity(0.38),
                    style: FillStyle(eoFill: true)
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

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
                    width: proxy.size.width,
                    panelHeight: layout.bottomPanelHeight
                )
            }
            .bindCameraCaptureViewfinder(to: cameraManager)
        }
        .navigationTitle(context.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(.title2, design: .default).weight(.medium))
                        .foregroundColor(Color(uiColor: .label))
                        .frame(width: 44, height: 44)
                }
            }

            ToolbarItem(placement: .principal) {
                Text(context.navigationTitle)
                    .font(.system(.largeTitle, design: .default).weight(.heavy))
                    .foregroundColor(Color(uiColor: .label))
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onShowGuide) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(.title3, design: .default).weight(.medium))
                        .foregroundColor(Color(uiColor: .label))
                        .frame(width: 44, height: 44)
                }
            }
        }
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .statusBarHidden(false)
    }
}

private extension ExaminationReportCameraScreen {
    var promptText: some View {
        Group {
            if capturedImages.isEmpty {
                Text(L10n.text(
                    "home.medical.examination_report.camera.prompt.default",
                    fallback: "保持报告四边完整入框，文字清晰无遮挡"
                ))
            } else {
                Text(
                    String(
                        format: L10n.text(
                            "home.medical.examination_report.camera.prompt.page",
                            fallback: "第 %d 张 · 保持报告四边完整入框"
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

    func bottomPanel(width: CGFloat, panelHeight: CGFloat) -> some View {
        let metrics = ExaminationReportBottomPanelMetrics(panelHeight: panelHeight)

        return VStack(spacing: metrics.rowSpacing) {
            thumbnailScrollRow(metrics: metrics)

            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: metrics.titleIconSize, weight: .semibold))
                        .foregroundColor(accentColor)

                    Text(context.navigationTitle)
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
            .padding(.bottom, 16)
        }
        .frame(width: width, height: panelHeight, alignment: .top)
        .padding(.top, metrics.topPadding)
        .background(
            ExaminationReportTopRoundedRectangle(cornerRadius: 28)
                .fill(Color(uiColor: .systemBackground))
        )
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    func thumbnailScrollRow(metrics: ExaminationReportBottomPanelMetrics) -> some View {
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

    func emptyThumbnailPlaceholder(metrics: ExaminationReportBottomPanelMetrics) -> some View {
        RoundedRectangle(cornerRadius: metrics.thumbnailCornerRadius, style: .continuous)
            .stroke(Color(uiColor: .separator).opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .frame(width: metrics.thumbnailWidth, height: metrics.thumbnailHeight)
            .overlay {
                Image(systemName: "doc.text")
                    .font(.system(size: metrics.thumbnailHeight * 0.28, weight: .medium))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
    }

    func thumbnailItem(
        for item: ExaminationReportCapturedImage,
        metrics: ExaminationReportBottomPanelMetrics
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

private struct ExaminationReportCameraOutsideMask: Shape {
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

private struct ExaminationReportTopRoundedRectangle: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
