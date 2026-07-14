import Foundation

/// 医疗资源归档查询参数，对应服务端 `archived` query。
enum MedicalArchiveQuery: String, Sendable {
    case active = "false"
    case archived = "true"
    case all = "all"
}

/// 列表页归档展示模式（正常列表 / 归档列表）。
enum MedicalArchiveListMode: Sendable {
    case active
    case archived

    var query: MedicalArchiveQuery {
        switch self {
        case .active: return .active
        case .archived: return .archived
        }
    }
}
