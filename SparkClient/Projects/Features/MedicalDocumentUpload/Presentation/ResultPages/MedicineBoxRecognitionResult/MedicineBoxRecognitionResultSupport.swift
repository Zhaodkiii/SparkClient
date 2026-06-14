import SwiftUI

/// 标识当前正在编辑的药品索引和数据
struct MedicineBoxRecognitionEditor: Identifiable {
    let index: Int
    let item: MedicineBoxRecognitionDraft

    var id: String { "medicine-box-\(index)" }
}

struct MedicineBoxAttachmentTarget: Identifiable {
    let index: Int

    var id: String { "medicine-box-attachment-\(index)" }
    var title: String { "关联药品附件" }
}

/// 药箱识别结果页统一 Sheet 路由
enum MedicineBoxRecognitionSheet: Identifiable {
    case edit(MedicineBoxRecognitionEditor)
    case attachments(MedicineBoxAttachmentTarget)

    var id: String {
        switch self {
        case .edit(let editor):
            return "edit-\(editor.id)"
        case .attachments(let target):
            return "attachments-\(target.id)"
        }
    }
}
