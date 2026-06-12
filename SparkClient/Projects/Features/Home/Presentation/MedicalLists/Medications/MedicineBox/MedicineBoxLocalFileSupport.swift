import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// 药箱相机拍摄图片的本地临时文件处理
enum MedicineBoxLocalFileSupport {
    /// 将药箱相机拍摄的图片写入临时目录，供识别流程使用
    static func saveCameraImageToTemp(
        _ image: UIImage,
        slot: MedicineBoxCaptureSlot? = nil,
        logger: Logger
    ) -> MedicalUploadLocalFile? {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
        let slotSuffix = slot.map { "_\($0.fileNameSuffix)" } ?? ""
        let filename = "medicine_box_camera\(slotSuffix)_\(UUID().uuidString).jpg"
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: target, options: .atomic)
            return MedicalUploadLocalFile(
                url: target,
                displayName: filename,
                mimeType: UTType.jpeg.preferredMIMEType
            )
        } catch {
            logger.error("写入药箱拍摄临时文件失败：\(error.localizedDescription)", module: .medical)
            return nil
        }
    }

    /// 批量保存相机返回的多张图片
    static func saveCapturedImages(
        _ images: [MedicineBoxCapturedImage],
        logger: Logger
    ) -> [MedicalUploadLocalFile] {
        images.compactMap { saveCameraImageToTemp($0.image, slot: $0.slot, logger: logger) }
    }
}
