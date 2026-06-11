import AVFoundation
import SwiftUI
import UIKit

private enum MedicineBoxCameraSheet: Identifiable {
    case guide(isFirstLaunch: Bool)

    var id: String {
        switch self {
        case .guide(let isFirstLaunch):
            return "guide:\(isFirstLaunch)"
        }
    }
}

/// 家庭药箱 AI 拍照识别专用相机场景（三槽位连续拍摄）。
struct MedicineBoxCameraSceneView: View {
    let onCancel: () -> Void
    let onImagesCaptured: ([MedicineBoxCapturedImage]) -> Void

    @State private var cameraManager = CustomCameraManager(
        captureSession: AVCaptureSession(),
        captureDeviceInputType: AVCaptureDeviceInput.self
    )
    @State private var presentedSheet: MedicineBoxCameraSheet?
    @State private var selectedSlot: MedicineBoxCaptureSlot = .front
    @State private var capturedImages: [MedicineBoxCaptureSlot: UIImage] = [:]
    @State private var missingRequiredMessage: String?
    @State private var previewInput: FilePreviewInput?
    @State private var previewTempFileURL: URL?

    init(
        onCancel: @escaping () -> Void,
        onImagesCaptured: @escaping ([MedicineBoxCapturedImage]) -> Void
    ) {
        self.onCancel = onCancel
        self.onImagesCaptured = onImagesCaptured
        if !MedicineBoxCameraGuideStore.shared.hasSeenGuide {
            _presentedSheet = State(initialValue: .guide(isFirstLaunch: true))
        }
    }

    private var canFinish: Bool {
        capturedImages[.front] != nil && capturedImages[.expiry] != nil
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
                    MedicineBoxCameraScreen(
                        cameraManager: cameraManager,
                        namespace: namespace,
                        closeCustomCameraAction: closeAction,
                        onCancel: onCancel,
                        onShowGuide: { presentedSheet = .guide(isFirstLaunch: false) },
                        onFinish: finishCapture,
                        onPreviewSlot: previewSlot,
                        onDeleteSlot: deleteSlotImage,
                        canFinish: canFinish,
                        selectedSlot: $selectedSlot,
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
                MedicineBoxCameraGuideView {
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
            missingRequiredMessage ?? "",
            isPresented: Binding(
                get: { missingRequiredMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        missingRequiredMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.text("common.got_it", fallback: "知道了"), role: .cancel) {}
        }
    }
}

private extension MedicineBoxCameraSceneView {
    func dismissGuide(isFirstLaunch: Bool) {
        if isFirstLaunch {
            MedicineBoxCameraGuideStore.shared.markAsSeen()
        }
        presentedSheet = nil
    }

    func handleConfirmedCapture(_ image: UIImage) {
        let slot = selectedSlot
        capturedImages[slot] = image
        cameraManager.setCapturedMedia(nil)
        advanceSlot(after: slot)

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "MedicineBoxCameraSceneView: slot=\(slot.rawValue) captured count=\(capturedImages.count)"
        )
    }

    func advanceSlot(after slot: MedicineBoxCaptureSlot) {
        let all = MedicineBoxCaptureSlot.allCases
        guard let index = all.firstIndex(of: slot) else { return }

        for nextIndex in (index + 1)..<all.count where capturedImages[all[nextIndex]] == nil {
            selectedSlot = all[nextIndex]
            return
        }

        if let firstEmpty = all.first(where: { capturedImages[$0] == nil }) {
            selectedSlot = firstEmpty
        }
    }

    func finishCapture() {
        let frontCaptured = capturedImages[.front] != nil
        let instructionCaptured = capturedImages[.expiry] != nil

        if let message = MedicineBoxCaptureSlot.missingRequiredMessage(
            frontCaptured: frontCaptured,
            instructionCaptured: instructionCaptured
        ) {
            missingRequiredMessage = message
            return
        }

        let results = MedicineBoxCaptureSlot.allCases.compactMap { slot -> MedicineBoxCapturedImage? in
            guard let image = capturedImages[slot] else { return nil }
            return MedicineBoxCapturedImage(slot: slot, image: image)
        }
        onImagesCaptured(results)
    }

    func previewSlot(_ slot: MedicineBoxCaptureSlot) {
        guard let image = capturedImages[slot] else { return }
        cleanupPreviewTempFile()

        guard let data = image.jpegData(compressionQuality: 0.95) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("medicine_box_preview_\(slot.rawValue)_\(UUID().uuidString).jpg")

        do {
            try data.write(to: url, options: .atomic)
            previewTempFileURL = url
            previewInput = FilePreviewInput(fileURL: url, displayName: slot.title)
        } catch {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "MedicineBoxCameraSceneView: preview temp file write failed slot=\(slot.rawValue)"
            )
        }
    }

    func deleteSlotImage(_ slot: MedicineBoxCaptureSlot) {
        capturedImages.removeValue(forKey: slot)
    }

    func cleanupPreviewTempFile() {
        if let previewTempFileURL {
            try? FileManager.default.removeItem(at: previewTempFileURL)
        }
        previewTempFileURL = nil
    }
}

/// 底部面板尺寸基准（原固定布局，以 `panelHeight = 268` 为设计稿参考高度）。
private enum MedicineBoxBottomPanelBaseline {
    static let panelHeight: CGFloat = 268
    static let topPadding: CGFloat = 18
    static let rowSpacing: CGFloat = 24
    static let slotThumbnailHeight: CGFloat = 88
    static let slotLabelSpacing: CGFloat = 6
    static let slotCornerRadius: CGFloat = 10
    static let placeholderIconSize: CGFloat = 22
    static let captureButtonOuter: CGFloat = 84
    static let captureButtonInner: CGFloat = 68
    static let captureStrokeWidth: CGFloat = 6
    static let captureIconSize: CGFloat = 28
    static let sideActionWidth: CGFloat = 88
    static let deleteButtonSize: CGFloat = 28
    static let deleteIconSize: CGFloat = 11
    static let deleteButtonOffset: CGFloat = 6
    static let finishHorizontalPadding: CGFloat = 18
    static let finishVerticalPadding: CGFloat = 10
    static let finishCornerRadius: CGFloat = 12
    static let titleIconSize: CGFloat = 18
}

/// 根据实际 `panelHeight` 按设计稿比例缩放底部面板各元素尺寸。
private struct MedicineBoxBottomPanelMetrics {
    let panelHeight: CGFloat

    private var scale: CGFloat {
        panelHeight / MedicineBoxBottomPanelBaseline.panelHeight
    }

    /// 将设计稿原值按 `panelHeight` 比例换算为当前屏幕尺寸。
    private func scaled(_ baseline: CGFloat) -> CGFloat {
        baseline * scale
    }

    var topPadding: CGFloat { scaled(MedicineBoxBottomPanelBaseline.topPadding) }
    var rowSpacing: CGFloat { scaled(MedicineBoxBottomPanelBaseline.rowSpacing) }
    var slotThumbnailHeight: CGFloat { scaled(MedicineBoxBottomPanelBaseline.slotThumbnailHeight) }
    var slotLabelSpacing: CGFloat { scaled(MedicineBoxBottomPanelBaseline.slotLabelSpacing) }
    var slotCornerRadius: CGFloat { scaled(MedicineBoxBottomPanelBaseline.slotCornerRadius) }
    var placeholderIconSize: CGFloat { scaled(MedicineBoxBottomPanelBaseline.placeholderIconSize) }
    var captureButtonOuter: CGFloat { scaled(MedicineBoxBottomPanelBaseline.captureButtonOuter) }
    var captureButtonInner: CGFloat { scaled(MedicineBoxBottomPanelBaseline.captureButtonInner) }
    var captureStrokeWidth: CGFloat { scaled(MedicineBoxBottomPanelBaseline.captureStrokeWidth) }
    var captureIconSize: CGFloat { scaled(MedicineBoxBottomPanelBaseline.captureIconSize) }
    var sideActionWidth: CGFloat { scaled(MedicineBoxBottomPanelBaseline.sideActionWidth) }
    var deleteButtonSize: CGFloat { scaled(MedicineBoxBottomPanelBaseline.deleteButtonSize) }
    var deleteIconSize: CGFloat { scaled(MedicineBoxBottomPanelBaseline.deleteIconSize) }
    var deleteButtonOffset: CGFloat { scaled(MedicineBoxBottomPanelBaseline.deleteButtonOffset) }
    var finishHorizontalPadding: CGFloat { scaled(MedicineBoxBottomPanelBaseline.finishHorizontalPadding) }
    var finishVerticalPadding: CGFloat { scaled(MedicineBoxBottomPanelBaseline.finishVerticalPadding) }
    var finishCornerRadius: CGFloat { scaled(MedicineBoxBottomPanelBaseline.finishCornerRadius) }
    var titleIconSize: CGFloat { scaled(MedicineBoxBottomPanelBaseline.titleIconSize) }
}

/// 药盒相机取景器与底部面板的响应式布局计算。
private struct MedicineBoxViewfinderLayout {
    let viewfinderRect: CGRect
    let bottomPanelHeight: CGFloat
    let promptY: CGFloat

    init(proxy: GeometryProxy) {
        let availableWidth = proxy.size.width
        let availableHeight = proxy.size.height
        let safeTop = proxy.safeAreaInsets.top
        let safeBottom = proxy.safeAreaInsets.bottom

        // 底部面板高度：屏幕高度的 26%，且不低于 220pt。
        let bottomPanelHeight = max(220, availableHeight * 0.26)
        // 顶部工具栏占用高度（安全区 + 工具栏内容）。
        let topToolbarHeight = safeTop + 64
        let promptHeight: CGFloat = 52
        // 取景器与顶部工具栏的间距（略大于底部间距，使取景器整体偏下）。
        let topVerticalGap: CGFloat = 22
        // 提示文案与底部面板之间的间距。
        let bottomVerticalGap: CGFloat = 8
        // 取景器下沿与提示文案之间的间距。
        let viewfinderPromptGap: CGFloat = 12

        // 可用于放置取景器的垂直区域上下边界。
        let cameraAreaTop = topToolbarHeight + topVerticalGap
        let cameraAreaBottom = availableHeight - safeBottom - bottomPanelHeight - promptHeight - bottomVerticalGap
        let cameraAreaHeight = max(220, cameraAreaBottom - cameraAreaTop)

        // 取景器宽高：宽度不超过屏幕 92% 且上限 460pt；高度受可用区域与宽高比约束。
        let viewfinderWidth = min(availableWidth * 0.92, 460)
        let viewfinderHeight = min(cameraAreaHeight * 0.92, viewfinderWidth * 1.18)
        // 取景器中心 Y：在可用区域内略偏下（0.52），远离顶部、靠近底部面板。
        let viewfinderCenterY = cameraAreaTop + cameraAreaHeight * 0.52

        self.bottomPanelHeight = bottomPanelHeight
        self.viewfinderRect = CGRect(
            x: (availableWidth - viewfinderWidth) / 2,
            y: viewfinderCenterY - viewfinderHeight / 2,
            width: viewfinderWidth,
            height: viewfinderHeight
        )
        // 提示文案 Y：紧跟取景器下方，同时不超过底部面板上方的安全位置。
        self.promptY = min(
            viewfinderRect.maxY + viewfinderPromptGap + promptHeight / 2,
            availableHeight - safeBottom - bottomPanelHeight - bottomVerticalGap - promptHeight / 2
        )
    }
}

private struct MedicineBoxCameraScreen: CustomCameraScreen {
    @ObservedObject var cameraManager: CustomCameraManager
    let namespace: Namespace.ID
    let closeCustomCameraAction: () -> Void
    let onCancel: () -> Void
    let onShowGuide: () -> Void
    let onFinish: () -> Void
    let onPreviewSlot: (MedicineBoxCaptureSlot) -> Void
    let onDeleteSlot: (MedicineBoxCaptureSlot) -> Void
    let canFinish: Bool

    @Binding var selectedSlot: MedicineBoxCaptureSlot
    @Binding var capturedImages: [MedicineBoxCaptureSlot: UIImage]

    @State private var isCapturing = false

    private let capturePurple = Color(uiColor: .systemPurple)

    var body: some View {
        GeometryReader { proxy in
            let layout = MedicineBoxViewfinderLayout(proxy: proxy)
            let safeBottom = proxy.safeAreaInsets.bottom
            let panelTotalHeight = layout.bottomPanelHeight + safeBottom

            ZStack {
                createCameraOutputView()
                    .ignoresSafeArea()

                MedicineBoxCameraOutsideMask(
                    cutoutRect: layout.viewfinderRect,
                    cornerRadius: min(layout.viewfinderRect.width, layout.viewfinderRect.height) * 0.09
                )
                .fill(
                    Color.black.opacity(0.38),
                    style: FillStyle(eoFill: true)
                )
                .ignoresSafeArea()

                MedicineBoxCameraViewfinderShape()
                    .stroke(
                        Color.white,
                        style: StrokeStyle(
                            lineWidth: 5,
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
        .navigationTitle(L10n.text("home.medical.medicine_box.camera.title", fallback: "药盒"))
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
                Text(L10n.text("home.medical.medicine_box.camera.title", fallback: "药盒"))
                    .font(.system(.largeTitle, design: .default).weight(.heavy))
                    .foregroundColor(.white)
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: onShowGuide) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(.title3, design: .default).weight(.medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }

//                Button(action: flipCamera) {
//                    Image(systemName: "arrow.triangle.2.circlepath.camera")
//                        .font(.system(.title3, design: .default).weight(.medium))
//                        .foregroundColor(.white)
//                        .frame(width: 44, height: 44)
//                }
//                .disabled(isCapturing)
//                .opacity(isCapturing ? 0.6 : 1)
            }
        }
        .statusBarHidden(false)
    }
}

private extension MedicineBoxCameraScreen {
    var promptText: some View {
        Text(selectedSlot.capturePrompt)
            .font(.system(.headline, design: .default).weight(.bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 36)
            .animation(.easeInOut(duration: 0.2), value: selectedSlot)
    }

    func bottomPanel(safeBottom: CGFloat, width: CGFloat, panelHeight: CGFloat) -> some View {
        let metrics = MedicineBoxBottomPanelMetrics(panelHeight: panelHeight)

        return VStack(spacing: metrics.rowSpacing) {
            slotPreviewRow(metrics: metrics)

            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: metrics.titleIconSize, weight: .semibold))
                        .foregroundColor(capturePurple)

                    Text(L10n.text("home.medical.medicine_box.camera.title", fallback: "药盒"))
                        .font(.system(.title3, design: .default).weight(.bold))
                        .foregroundColor(Color(uiColor: .label))
                }
                .frame(width: metrics.sideActionWidth)

                Spacer(minLength: 0)

                Button(action: capturePhoto) {
                    ZStack {
                        Circle()
                            .stroke(capturePurple.opacity(0.35), lineWidth: metrics.captureStrokeWidth)
                            .frame(width: metrics.captureButtonOuter, height: metrics.captureButtonOuter)

                        Circle()
                            .fill(capturePurple)
                            .frame(width: metrics.captureButtonInner, height: metrics.captureButtonInner)

                        Image(systemName: "camera.fill")
                            .font(.system(size: metrics.captureIconSize, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCapturing)
                .opacity(isCapturing ? 0.7 : 1)
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
                                        ? capturePurple
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

    func slotPreviewRow(metrics: MedicineBoxBottomPanelMetrics) -> some View {
        HStack(spacing: 12) {
            ForEach(MedicineBoxCaptureSlot.allCases) { slot in
                slotPreviewItem(for: slot, metrics: metrics)
            }
        }
        .padding(.horizontal, 20)
    }

    func slotPreviewItem(
        for slot: MedicineBoxCaptureSlot,
        metrics: MedicineBoxBottomPanelMetrics
    ) -> some View {
        let isSelected = selectedSlot == slot
        let image = capturedImages[slot]
        let thumbnailHeight = metrics.slotThumbnailHeight

        return VStack(spacing: metrics.slotLabelSpacing) {
            ZStack(alignment: .topTrailing) {
                Button {
                    handleSlotTap(slot)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: metrics.slotCornerRadius, style: .continuous)
                            .fill(
                                isSelected
                                    ? capturePurple.opacity(0.12)
                                    : Color(uiColor: .secondarySystemBackground)
                            )
                            .frame(height: thumbnailHeight)

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: thumbnailHeight)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: metrics.slotCornerRadius, style: .continuous)
                                )
                        } else {
                            Image(systemName: slot.placeholderSystemImage)
                                .font(.system(size: metrics.placeholderIconSize, weight: .semibold))
                                .foregroundColor(
                                    isSelected ? capturePurple : Color(uiColor: .tertiaryLabel)
                                )
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.slotCornerRadius, style: .continuous)
                            .stroke(
                                isSelected ? capturePurple : Color(uiColor: .separator).opacity(0.5),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)

                if image != nil {
                    Button {
                        onDeleteSlot(slot)
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

            Text(slot.displayTitle)
                .font(.system(.caption, design: .default).weight(isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? capturePurple : Color(uiColor: .secondaryLabel))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    func handleSlotTap(_ slot: MedicineBoxCaptureSlot) {
        if selectedSlot == slot, capturedImages[slot] != nil {
            onPreviewSlot(slot)
        } else {
            selectedSlot = slot
        }
    }

    func capturePhoto() {
        guard !isCapturing else { return }

        isCapturing = true
        setOutputType(.photo)
        captureOutput()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isCapturing = false
        }
    }

    func flipCamera() {
        guard !isCapturing else { return }

        Task {
            do {
                try await setCameraPosition(cameraPosition.next())
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                SparkLogger.log(
                    level: .warning,
                    module: .camera,
                    message: "MedicineBoxCameraSceneView: 切换摄像头失败 error=\(error.localizedDescription)"
                )
            }
        }
    }
}

private struct MedicineBoxCameraOutsideMask: Shape {
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
