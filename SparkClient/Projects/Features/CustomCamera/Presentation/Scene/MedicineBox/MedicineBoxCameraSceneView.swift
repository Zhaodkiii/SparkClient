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

/// 家庭药箱 AI 拍照识别专用相机场景。
struct MedicineBoxCameraSceneView: View {
    let onCancel: () -> Void
    let onPickPhoto: () -> Void
    let onImageCaptured: (UIImage) -> Void

    @State private var cameraManager = CustomCameraManager(
        captureSession: AVCaptureSession(),
        captureDeviceInputType: AVCaptureDeviceInput.self
    )
    @State private var presentedSheet: MedicineBoxCameraSheet?

    init(
        onCancel: @escaping () -> Void,
        onPickPhoto: @escaping () -> Void,
        onImageCaptured: @escaping (UIImage) -> Void
    ) {
        self.onCancel = onCancel
        self.onPickPhoto = onPickPhoto
        self.onImageCaptured = onImageCaptured
        if !MedicineBoxCameraGuideStore.shared.hasSeenGuide {
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
                .setCapturedMediaScreen(DefaultCustomCapturedMediaScreen.init)
                .setCameraScreen { cameraManager, namespace, closeAction in
                    MedicineBoxCameraScreen(
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
                        message: "MedicineBoxCameraSceneView: 图片采集回调 size=\(Int(image.size.width))x\(Int(image.size.height))"
                    )
                    onImageCaptured(image)
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
    }
}

private extension MedicineBoxCameraSceneView {
    func dismissGuide(isFirstLaunch: Bool) {
        if isFirstLaunch {
            MedicineBoxCameraGuideStore.shared.markAsSeen()
        }
        presentedSheet = nil
    }
}

private struct MedicineBoxCameraScreen: CustomCameraScreen {
    @ObservedObject var cameraManager: CustomCameraManager
    let namespace: Namespace.ID
    let closeCustomCameraAction: () -> Void
    let onCancel: () -> Void
    let onPickPhoto: () -> Void
    let onShowGuide: () -> Void

    @State private var isCapturing = false

    private let panelHeight: CGFloat = 220
    private let capturePurple = Color(uiColor: .systemPurple)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom

            let viewfinderWidth = min(size.width * 0.87, 420)
            let viewfinderHeight = viewfinderWidth * 0.92
            let viewfinderY = max(safeTop + 170, size.height * 0.27)

            let viewfinderRect = CGRect(
                x: (size.width - viewfinderWidth) / 2,
                y: viewfinderY,
                width: viewfinderWidth,
                height: viewfinderHeight
            )

            ZStack {
                createCameraOutputView()
                    .ignoresSafeArea()

                MedicineBoxCameraOutsideMask(
                    cutoutRect: viewfinderRect,
                    cornerRadius: 22
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
                    .frame(width: viewfinderRect.width, height: viewfinderRect.height)
                    .cameraCaptureViewfinder()
                    .position(x: viewfinderRect.midX, y: viewfinderRect.midY)

                promptText
                    .position(
                        x: size.width / 2,
                        y: viewfinderRect.maxY + 72
                    )

                bottomPanel(safeBottom: safeBottom, width: size.width)
            }
            .bindCameraCaptureViewfinder(to: cameraManager)
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("药盒")
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
                Text("药盒")
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

                Button(action: flipCamera) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(.title3, design: .default).weight(.medium))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .disabled(isCapturing)
                .opacity(isCapturing ? 0.6 : 1)
            }
        }
        .statusBarHidden(false)
    }
}

private extension MedicineBoxCameraScreen {
    var promptText: some View {
        Text("保证药品名称、品牌、规格完整，拍摄清晰")
            .font(.system(.headline, design: .default).weight(.bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 36)
    }

    func bottomPanel(safeBottom: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(capturePurple)

                Text("药盒")
                    .font(.system(.title3, design: .default).weight(.bold))
                    .foregroundColor(Color(uiColor: .label))

                Spacer()

                Button(action: onPickPhoto) {
                    Label("相册", systemImage: "photo.on.rectangle")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundColor(capturePurple)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Button(action: capturePhoto) {
                ZStack {
                    Circle()
                        .stroke(capturePurple.opacity(0.35), lineWidth: 6)
                        .frame(width: 92, height: 92)

                    Circle()
                        .fill(capturePurple)
                        .frame(width: 76, height: 76)

                    Image(systemName: "camera.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(isCapturing)
            .opacity(isCapturing ? 0.7 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCapturing)
            .padding(.bottom, max(safeBottom, 20) + 8)
        }
        .frame(width: width, height: panelHeight + safeBottom)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .ignoresSafeArea(edges: .bottom)
        )
        .frame(maxHeight: .infinity, alignment: .bottom)
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
