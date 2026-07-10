import Combine
import Foundation
import UIKit

/// 药盒固定槽位拍摄工作流。
@MainActor
final class MedicineBoxCaptureWorkflow: ObservableObject {
    @Published var selectedSlot: MedicineBoxCaptureSlot = .front
    @Published private(set) var capturedImages: [MedicineBoxCaptureSlot: UIImage] = [:]

    var canFinish: Bool {
        capturedImages[.front] != nil && capturedImages[.expiry] != nil
    }

    var prompt: String {
        selectedSlot.capturePrompt
    }

    var capturedCount: Int {
        capturedImages.count
    }

    func capture(_ image: UIImage) {
        let slot = selectedSlot
        capturedImages[slot] = image
        advanceSlot(after: slot)

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "MedicalDocumentCameraSceneHost: context=medicineBox slot=\(slot.rawValue) capturedCount=\(capturedImages.count)"
        )
    }

    func deleteSlot(_ slot: MedicineBoxCaptureSlot) {
        capturedImages.removeValue(forKey: slot)
    }

    func image(for slot: MedicineBoxCaptureSlot) -> UIImage? {
        capturedImages[slot]
    }

    /// 完成校验。成功返回有序结果；失败返回提示文案。
    func finish() -> (images: [MedicineBoxCapturedImage]?, message: String?) {
        if let message = MedicineBoxCaptureSlot.missingRequiredMessage(
            frontCaptured: capturedImages[.front] != nil,
            expiryCaptured: capturedImages[.expiry] != nil
        ) {
            return (nil, message)
        }

        let results = MedicineBoxCaptureSlot.allCases.compactMap { slot -> MedicineBoxCapturedImage? in
            guard let image = capturedImages[slot] else { return nil }
            return MedicineBoxCapturedImage(slot: slot, image: image)
        }
        return (results, nil)
    }

    private func advanceSlot(after slot: MedicineBoxCaptureSlot) {
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
}
