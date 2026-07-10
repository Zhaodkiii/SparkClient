import AVFoundation
import SwiftUI
import UIKit

private enum MedicalDocumentCameraSheet: Identifiable {
    case guide(isFirstLaunch: Bool)

    var id: String {
        switch self {
        case .guide(let isFirstLaunch):
            return "guide:\(isFirstLaunch)"
        }
    }
}

/// 医疗文档公共相机会话宿主：会话、媒体确认、Sheet、Alert 与场景销毁。
struct MedicalDocumentCameraSceneHost<BottomContent: View, GuideContent: View>: View {
    let configuration: MedicalDocumentCameraConfiguration
    let prompt: String
    let canFinish: Bool
    let canCapture: Bool
    let onCancel: () -> Void
    let onFinish: () -> Void
    let onConfirmedCapture: (UIImage) -> Void
    let onCaptureBlocked: (() -> Void)?
    let alertMessage: Binding<String?>
    @ObservedObject var previewStore: MedicalDocumentCameraPreviewStore
    @ViewBuilder let guideContent: (_ onDismiss: @escaping () -> Void) -> GuideContent
    @ViewBuilder let bottomContent: (MedicalDocumentCameraBottomPanelContext) -> BottomContent

    @State private var cameraManager = CustomCameraManager(
        captureSession: AVCaptureSession(),
        captureDeviceInputType: AVCaptureDeviceInput.self
    )
    @State private var presentedSheet: MedicalDocumentCameraSheet?

    init(
        configuration: MedicalDocumentCameraConfiguration,
        prompt: String,
        canFinish: Bool,
        canCapture: Bool,
        onCancel: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onConfirmedCapture: @escaping (UIImage) -> Void,
        onCaptureBlocked: (() -> Void)? = nil,
        alertMessage: Binding<String?>,
        previewStore: MedicalDocumentCameraPreviewStore,
        @ViewBuilder guideContent: @escaping (_ onDismiss: @escaping () -> Void) -> GuideContent,
        @ViewBuilder bottomContent: @escaping (MedicalDocumentCameraBottomPanelContext) -> BottomContent
    ) {
        self.configuration = configuration
        self.prompt = prompt
        self.canFinish = canFinish
        self.canCapture = canCapture
        self.onCancel = onCancel
        self.onFinish = onFinish
        self.onConfirmedCapture = onConfirmedCapture
        self.onCaptureBlocked = onCaptureBlocked
        self.alertMessage = alertMessage
        self.previewStore = previewStore
        self.guideContent = guideContent
        self.bottomContent = bottomContent

        if !MedicalDocumentCameraGuideStore.shared.hasSeenGuide(for: configuration.context) {
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
                    MedicalDocumentCameraScreenShell(
                        cameraManager: cameraManager,
                        namespace: namespace,
                        closeCustomCameraAction: closeAction,
                        configuration: configuration,
                        prompt: prompt,
                        canFinish: canFinish,
                        canCapture: canCapture,
                        onCancel: onCancel,
                        onShowGuide: { presentedSheet = .guide(isFirstLaunch: false) },
                        onFinish: onFinish,
                        onCaptureBlocked: onCaptureBlocked,
                        bottomContent: bottomContent
                    )
                }
                .setCloseCustomCameraAction(onCancel)
                .onImageCaptured { image, _ in
                    onConfirmedCapture(image)
                    cameraManager.setCapturedMedia(nil)
                }
                // CAMERA-000005：拍摄页取消根级忽略安全区，布局按安全区内坐标系计算。
                .startSession()
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .guide(let isFirstLaunch):
                guideContent {
                    dismissGuide(isFirstLaunch: isFirstLaunch)
                }
                .interactiveDismissDisabled()
            }
        }
        .sheet(item: $previewStore.previewInput) { input in
            QuickLookPreviewBridge(inputs: [input], startIndex: 0)
                .onDisappear {
                    previewStore.cleanup()
                }
        }
        .alert(
            alertMessage.wrappedValue ?? "",
            isPresented: Binding(
                get: { alertMessage.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        alertMessage.wrappedValue = nil
                    }
                }
            )
        ) {
            Button(L10n.text("common.got_it", fallback: "知道了"), role: .cancel) {}
        }
        .onDisappear {
            previewStore.cleanup()
        }
    }

    private func dismissGuide(isFirstLaunch: Bool) {
        if isFirstLaunch {
            MedicalDocumentCameraGuideStore.shared.markAsSeen(for: configuration.context)
        }
        presentedSheet = nil
    }
}
