import AVFoundation
import SwiftUI
import UIKit

private enum NutritionFoodCameraSheet: Identifiable {
    case guide(isFirstLaunch: Bool)
    case confirmCapture(CameraCapturePending)

    var id: String {
        switch self {
        case .guide(let isFirstLaunch):
            return "guide:\(isFirstLaunch)"
        case .confirmCapture(let pending):
            return "confirmCapture:\(pending.id)"
        }
    }
}

struct NutritionFoodCameraSceneView: View {
    let onCancel: () -> Void
    let onPickPhoto: () -> Void
    let onImageCaptured: (UIImage) -> Void

    @State private var cameraManager = CustomCameraManager(
        captureSession: AVCaptureSession(),
        captureDeviceInputType: AVCaptureDeviceInput.self
    )
    @State private var presentedSheet: NutritionFoodCameraSheet?

    init(
        onCancel: @escaping () -> Void,
        onPickPhoto: @escaping () -> Void,
        onImageCaptured: @escaping (UIImage) -> Void
    ) {
        self.onCancel = onCancel
        self.onPickPhoto = onPickPhoto
        self.onImageCaptured = onImageCaptured
        if !NutritionFoodCameraGuideStore.shared.hasSeenGuide {
            _presentedSheet = State(initialValue: .guide(isFirstLaunch: true))
        }
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            CustomCameraView(manager: cameraManager)
                .setCameraOutputType(.photo)
                .setCameraPosition(.back)
                .setAudioAvailability(false)
                .setGridVisibility(false)
                .setLightMode(.off)
                .setCapturedMediaScreen(nil)
                .setCameraScreen { cameraManager, namespace, closeAction in
                    NutritionFoodCameraScreen(
                        cameraManager: cameraManager,
                        namespace: namespace,
                        closeCustomCameraAction: closeAction,
                        onCancel: onCancel,
                        onPickPhoto: onPickPhoto,
                        onShowGuide: { presentedSheet = .guide(isFirstLaunch: false) }
                    )
                }
                .setCloseCustomCameraAction(onCancel)
                .onImageCaptured { image, _ in
                    SparkLogger.log(
                        level: .info,
                        module: .camera,
                        message: "NutritionFoodCameraSceneView: 图片采集回调 size=\(Int(image.size.width))x\(Int(image.size.height))"
                    )
                    presentConfirmation(for: image)
                }
                // CAMERA-000005：拍摄页取消根级忽略安全区，布局按安全区内坐标系计算。
                .startSession()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .guide(let isFirstLaunch):
                NutritionFoodCameraGuideView {
                    dismissGuide(isFirstLaunch: isFirstLaunch)
                }
                .interactiveDismissDisabled()
            case .confirmCapture(let capture):
                CameraCaptureConfirmView(
                    pending: capture,
                    onCancel: { cancelConfirmation(capture) },
                    onConfirm: { confirmConfirmation(capture) }
                )
                .interactiveDismissDisabled()
            }
        }
    }
}

private extension NutritionFoodCameraSceneView {
    func dismissGuide(isFirstLaunch: Bool) {
        if isFirstLaunch {
            NutritionFoodCameraGuideStore.shared.markAsSeen()
        }
        presentedSheet = nil
    }

    /// 拍摄完成后，弹出确认页面。
    func presentConfirmation(for image: UIImage) {
        guard let pending = CameraCapturePending.make(from: image) else {
            // 兜底：无法生成预览文件时，直接走完成回调。
            onImageCaptured(image)
            return
        }
        presentedSheet = .confirmCapture(pending)
    }

    /// 取消：关闭确认页面、清理临时文件，并清除已拍摄媒体以便重新拍摄。
    func cancelConfirmation(_ capture: CameraCapturePending) {
        capture.cleanup()
        presentedSheet = nil
        cameraManager.setCapturedMedia(nil)
    }

    /// 确认：关闭确认页面、清理临时文件，并回调完成拍摄。
    func confirmConfirmation(_ capture: CameraCapturePending) {
        let image = capture.image
        capture.cleanup()
        presentedSheet = nil
        onImageCaptured(image)
    }
}

private struct NutritionFoodCameraScreen: CustomCameraScreen {
    @ObservedObject var cameraManager: CustomCameraManager
    let namespace: Namespace.ID
    let closeCustomCameraAction: () -> Void
    let onCancel: () -> Void
    let onPickPhoto: () -> Void
    let onShowGuide: () -> Void

    @State private var isCapturing = false
    @State private var isTorchOn = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // CAMERA-000005：内容区已遵守安全区，取景框与底部控件不再额外叠加 safeTop/safeBottom。
            let viewfinderWidth = min(size.width * 0.84, 420)
            let viewfinderHeight = viewfinderWidth * 0.84
            let viewfinderY = max(170, size.height * 0.27)

            let viewfinderRect = CGRect(
                x: (size.width - viewfinderWidth) / 2,
                y: viewfinderY,
                width: viewfinderWidth,
                height: viewfinderHeight
            )

            ZStack {
                createCameraOutputView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                NutritionFoodCameraOutsideMask(
                    cutoutRect: viewfinderRect,
                    cornerRadius: 22
                )
                .fill(
                    Color.black.opacity(0.42),
                    style: FillStyle(eoFill: true)
                )
                .frame(width: size.width, height: size.height)

                NutritionFoodCameraViewfinderShape()
                    .stroke(
                        Color.white,
                        style: StrokeStyle(
                            lineWidth: 5,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: viewfinderRect.width, height: viewfinderRect.height)
                    .cameraCaptureViewfinder()
                    .position(x: viewfinderRect.midX, y: viewfinderRect.midY)

                promptText
                    .position(
                        x: size.width / 2,
                        y: viewfinderRect.maxY + 92
                    )

                bottomControls
                    .padding(.horizontal, 36)
                    .position(
                        x: size.width / 2,
                        y: size.height - 86
                    )
            }
            .bindCameraCaptureViewfinder(to: cameraManager)
        }
        .navigationTitle(L10n.text("nutrition.recognition.camera.title", fallback: "饮食识别"))
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
                Text(L10n.text("nutrition.recognition.camera.title", fallback: "饮食识别"))
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

private extension NutritionFoodCameraScreen {
    var promptText: some View {
        Text(L10n.text("nutrition.recognition.camera.prompt", fallback: "请确保在光线充足的环境中\n进行拍摄，且不超出镜头范围。"))
            .font(.system(.headline, design: .default).weight(.semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 42)
    }

    var bottomControls: some View {
        HStack(alignment: .center) {
            controlButton(
                systemImage: "photo.on.rectangle.angled",
                title: L10n.text("nutrition.recognition.camera.photo_library", fallback: "照片"),
                action: onPickPhoto
            )

            Spacer()

            Button(action: capturePhoto) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemMint))
                        .frame(width: 104, height: 104)
                        .shadow(
                            color: Color.black.opacity(0.45),
                            radius: 0,
                            x: 0,
                            y: 9
                        )

                    Image(systemName: "camera.fill")
                        .font(.system(.largeTitle, design: .default).weight(.bold))
                        .foregroundColor(Color(uiColor: .label))
                }
            }
            .buttonStyle(.plain)
            .disabled(isCapturing)
            .opacity(isCapturing ? 0.7 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCapturing)

            Spacer()

            controlButton(
                systemImage: isTorchOn ? "bolt.fill" : "bolt.slash.fill",
                title: L10n.text("nutrition.recognition.camera.flash", fallback: "闪光灯"),
                isEnabled: hasLight,
                action: toggleTorch
            )
        }
    }

    func controlButton(
        systemImage: String,
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(.title, design: .default).weight(.semibold))
                    .frame(width: 50, height: 38)

                Text(title)
                    .font(.system(.footnote, design: .default).weight(.medium))
            }
            .foregroundColor(.white)
            .frame(width: 74)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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

    func toggleTorch() {
        guard hasLight else { return }

        let nextMode: CameraLightMode = isTorchOn ? .off : .on

        do {
            try setLightMode(nextMode)
            isTorchOn.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            isTorchOn = false
        }
    }
}

private struct NutritionFoodCameraOutsideMask: Shape {
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
