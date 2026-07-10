import Combine
import Foundation
import UIKit

/// 报告类连续拍摄工作流：页码编号、上限校验与完成条件。
@MainActor
final class ReportDocumentCaptureWorkflow: ObservableObject {
    let context: MedicalDocumentCameraContext
    let maxCaptureCount: Int

    @Published private(set) var capturedImages: [ReportDocumentCapturedImage] = []

    init(context: MedicalDocumentCameraContext, maxCaptureCount: Int) {
        precondition(context.isReportDocument, "ReportDocumentCaptureWorkflow only accepts report contexts")
        self.context = context
        self.maxCaptureCount = max(1, maxCaptureCount)
    }

    var canFinish: Bool {
        capturedImages.isEmpty == false
    }

    var canCaptureMore: Bool {
        capturedImages.count < maxCaptureCount
    }

    var prompt: String {
        if capturedImages.isEmpty {
            return context.defaultPrompt
        }
        return String(
            format: context.pagePromptFormat,
            locale: Locale.current,
            capturedImages.count + 1
        )
    }

    /// 追加已确认图片。达到上限时返回 `false`。
    @discardableResult
    func appendCapturedImage(_ image: UIImage) -> Bool {
        guard canCaptureMore else { return false }

        let nextIndex = capturedImages.count + 1
        capturedImages.append(ReportDocumentCapturedImage(index: nextIndex, image: image))

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "MedicalDocumentCameraSceneHost: context=\(context.logContext) page=\(nextIndex) total=\(capturedImages.count) max=\(maxCaptureCount)"
        )
        return true
    }

    func deleteImage(_ item: ReportDocumentCapturedImage) {
        capturedImages.removeAll { $0.id == item.id }
        capturedImages = capturedImages.enumerated().map { offset, image in
            ReportDocumentCapturedImage(id: image.id, index: offset + 1, image: image.image)
        }
    }

    func finish() -> [ReportDocumentCapturedImage]? {
        guard canFinish else { return nil }
        return capturedImages
    }
}
