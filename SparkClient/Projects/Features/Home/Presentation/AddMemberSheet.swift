import Foundation

/// 首页弹出新增/编辑成员 Sheet 的标识。
enum AddMemberSheet: Identifiable, Equatable {
    case create(pendingShareTicket: String? = nil)
    case edit(Member)

    var id: String {
        switch self {
        case .create(let ticket):
            return "create-\(ticket ?? "new")"
        case .edit(let member):
            return "edit-\(member.id)"
        }
    }
}
