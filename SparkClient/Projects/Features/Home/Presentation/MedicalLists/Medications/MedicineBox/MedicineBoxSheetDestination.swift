import Foundation

/// 药箱表单 Sheet 路由状态
enum MedicineBoxSheetDestination: Identifiable {
    case create
    case serverEdit(SparkMedicalSyncAPI.RemoteMedicineBox)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .serverEdit(let box):
            return "server_\(box.id)"
        }
    }

    var formMode: MedicineBoxFormView.Mode {
        switch self {
        case .create:
            return .create
        case .serverEdit(let box):
            return .serverEdit(existing: box)
        }
    }
}
