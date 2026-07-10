import SwiftUI

/// 药盒固定槽位拍摄入口；内部组合公共 `MedicalDocumentCameraSceneHost`。
struct MedicineBoxCameraSceneView: View {
    let onCancel: () -> Void
    let onImagesCaptured: ([MedicineBoxCapturedImage]) -> Void

    @StateObject private var workflow = MedicineBoxCaptureWorkflow()
    @StateObject private var previewStore = MedicalDocumentCameraPreviewStore(logContext: "medicineBox")
    @State private var alertMessage: String?

    private var configuration: MedicalDocumentCameraConfiguration {
        MedicalDocumentCameraConfiguration(context: .medicineBox)
    }

    var body: some View {
        MedicalDocumentCameraSceneHost(
            configuration: configuration,
            prompt: workflow.prompt,
            canFinish: workflow.canFinish,
            canCapture: true,
            onCancel: onCancel,
            onFinish: finishCapture,
            onConfirmedCapture: workflow.capture,
            alertMessage: $alertMessage,
            previewStore: previewStore,
            guideContent: { dismiss in
                MedicineBoxCameraGuideContent(onDismiss: dismiss)
            },
            bottomContent: { panelContext in
                MedicineBoxCameraBottomPanel(
                    context: panelContext,
                    workflow: workflow,
                    onPreviewSlot: previewSlot
                )
            }
        )
    }

    private func finishCapture() {
        let result = workflow.finish()
        if let message = result.message {
            alertMessage = message
            return
        }
        if let images = result.images {
            onImagesCaptured(images)
        }
    }

    private func previewSlot(_ slot: MedicineBoxCaptureSlot) {
        guard let image = workflow.image(for: slot) else { return }
        previewStore.presentPreview(
            image: image,
            displayName: slot.title,
            fileTag: slot.rawValue
        )
    }
}
