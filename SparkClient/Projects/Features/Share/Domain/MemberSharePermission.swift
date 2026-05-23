import Foundation

/// 成员分享权限档位（§18），与服务端 ``permission`` 字段一致。
enum MemberSharePermission: String, CaseIterable, Identifiable, Sendable {
    case manage
    case edit
    case view

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .manage: return "home.members.share.permission.manage"
        case .edit: return "home.members.share.permission.edit"
        case .view: return "home.members.share.permission.view"
        }
    }

    var subtitleKey: String {
        switch self {
        case .manage: return "home.members.share.permission.manage.hint"
        case .edit: return "home.members.share.permission.edit.hint"
        case .view: return "home.members.share.permission.view.hint"
        }
    }
}
