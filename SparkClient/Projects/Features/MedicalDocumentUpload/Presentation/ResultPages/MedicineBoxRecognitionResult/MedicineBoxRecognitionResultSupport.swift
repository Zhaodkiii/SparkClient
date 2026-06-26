import SwiftUI

struct MedicineBoxAttachmentTarget: Identifiable {
    let index: Int

    var id: String { "medicine-box-\(index)" }
    var title: String { "关联药品附件" }
}
