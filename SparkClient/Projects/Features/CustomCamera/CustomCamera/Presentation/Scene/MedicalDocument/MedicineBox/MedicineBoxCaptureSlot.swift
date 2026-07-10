import Foundation
import UIKit

/// 药箱连续拍摄槽位：药盒正面 → 保质期 → 说明书。
enum MedicineBoxCaptureSlot: String, CaseIterable, Identifiable, Hashable {
    case front
    case expiry
    case instruction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front:
            return L10n.text("home.medical.medicine_box.camera.slot.front", fallback: "药盒正面")
        case .expiry:
            return L10n.text("home.medical.medicine_box.camera.slot.expiry", fallback: "保质期")
        case .instruction:
            return L10n.text("home.medical.medicine_box.camera.slot.instruction", fallback: "说明书")
        }
    }

    /// 底部槽位展示文案（必拍项前缀 `*`）。
    var displayTitle: String {
        guard isRequired else { return title }
        return String(
            format: L10n.text("home.medical.medicine_box.camera.slot.required_format", fallback: "* %@"),
            locale: Locale.current,
            title
        )
    }

    var isRequired: Bool {
        switch self {
        case .front, .expiry:
            return true
        case .instruction:
            return false
        }
    }

    var capturePrompt: String {
        switch self {
        case .front:
            return L10n.text(
                "home.medical.medicine_box.camera.prompt.front",
                fallback: "保证药品名称、品牌、规格完整，拍摄清晰"
            )
        case .expiry:
            return L10n.text(
                "home.medical.medicine_box.camera.prompt.expiry",
                fallback: "拍清楚生产日期、有效期、批号"
            )
        case .instruction:
            return L10n.text(
                "home.medical.medicine_box.camera.prompt.instruction",
                fallback: "拍清楚用法用量、禁忌、注意事项"
            )
        }
    }

    var placeholderSystemImage: String {
        switch self {
        case .front:
            return "cross.case.fill"
        case .expiry:
            return "calendar.badge.clock"
        case .instruction:
            return "doc.text.fill"
        }
    }

    /// 保存临时文件时使用的前缀片段。
    var fileNameSuffix: String { rawValue }

    /// 必拍项缺失时的完成提示文案。
    static func missingRequiredMessage(
        frontCaptured: Bool,
        expiryCaptured: Bool
    ) -> String? {
        switch (frontCaptured, expiryCaptured) {
        case (false, false):
            return L10n.text(
                "home.medical.medicine_box.camera.validation.missing_both",
                fallback: "请先拍摄药盒正面和保质期"
            )
        case (false, true):
            return L10n.text(
                "home.medical.medicine_box.camera.validation.missing_front",
                fallback: "请先拍摄药盒正面"
            )
        case (true, false):
            return L10n.text(
                "home.medical.medicine_box.camera.validation.missing_expiry",
                fallback: "请先拍摄保质期"
            )
        case (true, true):
            return nil
        }
    }
}

/// 药盒槽位拍摄结果，必须保留 `slot` 业务语义。
struct MedicineBoxCapturedImage: Identifiable, Equatable {
    let id: UUID
    let slot: MedicineBoxCaptureSlot
    let image: UIImage

    init(id: UUID = UUID(), slot: MedicineBoxCaptureSlot, image: UIImage) {
        self.id = id
        self.slot = slot
        self.image = image
    }

    static func == (lhs: MedicineBoxCapturedImage, rhs: MedicineBoxCapturedImage) -> Bool {
        lhs.id == rhs.id && lhs.slot == rhs.slot
    }
}
