import SwiftUI

struct MedicationAttachmentTarget: Identifiable {
    let index: Int

    var id: String { "medication-\(index)" }
    var title: String { "关联药品附件" }
}
