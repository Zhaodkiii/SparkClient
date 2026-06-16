import Foundation
import SwiftUI

func stockText(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) -> String {
    guard let q = box.totalQuantity else { return L10n.text("home.medical.medication_plan.stock_not_filled", fallback: "总量未填") }
    return String(
        format: L10n.text("home.medical.medication_plan.stock_format", fallback: "总量 %@"),
        locale: .current,
        q.formatted(.number.precision(.fractionLength(0...2)))
    )
}

func planStatusText(_ status: String) -> String {
    switch status {
    case "active":
        return L10n.text("home.medical.list.medications.status.active", fallback: "执行中")
    case "paused":
        return L10n.text("home.medical.list.medications.status.paused", fallback: "未开始")
    case "completed":
        return L10n.text("home.medical.list.medications.status.completed", fallback: "已完成")
    case "cancelled":
        return L10n.text("home.medical.list.medications.status.cancelled", fallback: "已取消")
    default:
        return status
    }
}
