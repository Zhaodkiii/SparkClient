/// 场景化相机入口，业务方可传入配置与结果处理逻辑。

import SwiftUI
import AVFoundation

struct CustomCameraScene: View {
    let configuration: CustomCameraSceneConfiguration
    let resultHandler: CustomCameraResultHandler
    let onDismiss: () -> Void

    /// 使用 @State 持有相机管理器，避免视图刷新时重建实例，
    /// 从而保证 setup/startSession 与拍摄操作的是同一个实例。
    @State private var cameraManager = CustomCameraManager(
        captureSession: AVCaptureSession(),
        captureDeviceInputType: AVCaptureDeviceInput.self
    )

    var body: some View {
        configuredCameraView
            .ignoresSafeArea()
    }

    private var configuredCameraView: some View {
        let base = CustomCameraView(manager: cameraManager)
            .setCameraOutputType(configuration.outputType)
            .setCameraPosition(configuration.cameraPosition)
            .setAudioAvailability(configuration.isAudioAvailable)
            .setGridVisibility(configuration.showsGrid)
            .setMirrorOutput(configuration.mirrorOutput)
            .setCloseCustomCameraAction(onDismiss)
            .onImageCaptured { _, controller in
                handleConfirmedCapture(from: controller)
            }
            .onVideoCaptured { _, controller in
                handleConfirmedCapture(from: controller)
            }

        if configuration.showsCapturedMediaPreview {
            return AnyView(
                base
                    .setCapturedMediaScreen(DefaultCustomCapturedMediaScreen.init)
                    .startSession()
            )
        }

        return AnyView(
            base
                .setCapturedMediaScreen(nil)
                .startSession()
        )
    }

    private func handleConfirmedCapture(from controller: CustomCameraView.Controller) {
        guard let media = controller.customCameraView.manager.attributes.capturedMedia else {
            onDismiss()
            return
        }
        let result = CustomCameraSceneResult(media: media)
        resultHandler.onConfirmed(result)
        onDismiss()
    }
}
