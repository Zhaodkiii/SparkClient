import SwiftUI

/// 报告类医疗文档连续拍摄入口（病历 / 检查报告 / 体检报告 / 处方 / 服药计划）。
struct ReportDocumentCameraSceneView: View {
    let context: MedicalDocumentCameraContext
    let maxCaptureCount: Int
    let onCancel: () -> Void
    let onImagesCaptured: ([ReportDocumentCapturedImage]) -> Void

    @StateObject private var workflow: ReportDocumentCaptureWorkflow
    @StateObject private var previewStore: MedicalDocumentCameraPreviewStore
    @State private var alertMessage: String?

    init(
        context: MedicalDocumentCameraContext,
        maxCaptureCount: Int,
        onCancel: @escaping () -> Void,
        onImagesCaptured: @escaping ([ReportDocumentCapturedImage]) -> Void
    ) {
        precondition(context.isReportDocument, "ReportDocumentCameraSceneView does not accept .medicineBox")
        self.context = context
        self.maxCaptureCount = max(1, maxCaptureCount)
        self.onCancel = onCancel
        self.onImagesCaptured = onImagesCaptured
        _workflow = StateObject(
            wrappedValue: ReportDocumentCaptureWorkflow(
                context: context,
                maxCaptureCount: maxCaptureCount
            )
        )
        _previewStore = StateObject(
            wrappedValue: MedicalDocumentCameraPreviewStore(logContext: context.logContext)
        )
    }

    private var configuration: MedicalDocumentCameraConfiguration {
        MedicalDocumentCameraConfiguration(context: context, maxCaptureCount: maxCaptureCount)
    }

    var body: some View {
        MedicalDocumentCameraSceneHost(
            configuration: configuration,
            prompt: workflow.prompt,
            canFinish: workflow.canFinish,
            canCapture: workflow.canCaptureMore,
            onCancel: onCancel,
            onFinish: finishCapture,
            onConfirmedCapture: handleConfirmedCapture,
            onCaptureBlocked: showCaptureLimitMessage,
            alertMessage: $alertMessage,
            previewStore: previewStore,
            guideContent: { dismiss in
                ReportDocumentCameraGuideContent(
                    context: context,
                    maxCaptureCount: maxCaptureCount,
                    onDismiss: dismiss
                )
            },
            bottomContent: { panelContext in
                ReportDocumentCameraBottomPanel(
                    context: panelContext,
                    emptyThumbnailIcon: context.emptyThumbnailIcon,
                    capturedImages: workflow.capturedImages,
                    onPreview: previewImage,
                    onDelete: workflow.deleteImage
                )
            }
        )
    }

    private func handleConfirmedCapture(_ image: UIImage) {
        if workflow.appendCapturedImage(image) == false {
            showCaptureLimitMessage()
        }
    }

    private func finishCapture() {
        guard let images = workflow.finish() else {
            alertMessage = context.emptyValidationMessage
            return
        }
        onImagesCaptured(images)
    }

    private func showCaptureLimitMessage() {
        alertMessage = context.captureLimitMessage
    }

    private func previewImage(_ item: ReportDocumentCapturedImage) {
        previewStore.presentPreview(
            image: item.image,
            displayName: String(
                format: context.previewPageFormat,
                locale: Locale.current,
                item.index
            ),
            fileTag: "page_\(item.index)"
        )
    }
}
