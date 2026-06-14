import Foundation

/// 首页统一 Sheet 路由
enum HomeSheet: Identifiable {
    case addMember(AddMemberSheet)
    case pendingInvites
    case memberDetail(memberID: Int)
    case share(Member)
    case taskCenter

    var id: String {
        switch self {
        case .addMember(let sheet):
            return "addMember-\(sheet.id)"
        case .pendingInvites:
            return "pendingInvites"
        case .memberDetail(let memberID):
            return "memberDetail-\(memberID)"
        case .share(let member):
            return "share-\(member.id)"
        case .taskCenter:
            return "taskCenter"
        }
    }
}

/// 首页统一全屏 Cover 路由
enum HomeFullScreenCover: Identifiable {
    case medicalDocumentUpload
    case customCamera

    var id: String {
        switch self {
        case .medicalDocumentUpload:
            return "medicalDocumentUpload"
        case .customCamera:
            return "customCamera"
        }
    }
}
