import Foundation

/// 首页统一 Sheet 路由
enum HomeSheet: Identifiable {
    case addMember(AddMemberSheet)
    case pendingInvites
    case memberDetail(memberID: Int)
    case memberModuleSetup(Member)
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
        case .memberModuleSetup(let member):
            return "memberModuleSetup-\(member.id)"
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

extension HomeSheetKind {
    init?(sheet: HomeSheet?) {
        guard let sheet else { return nil }
        switch sheet {
        case .addMember:
            self = .addMember
        case .pendingInvites:
            self = .pendingInvites
        case .memberDetail:
            self = .memberDetail
        case .memberModuleSetup:
            self = .memberModuleSetup
        case .share:
            self = .share
        case .taskCenter:
            self = .taskCenter
        }
    }
}

extension HomeFullScreenCoverKind {
    init?(cover: HomeFullScreenCover?) {
        guard let cover else { return nil }
        switch cover {
        case .medicalDocumentUpload:
            self = .medicalDocumentUpload
        case .customCamera:
            self = .customCamera
        }
    }
}
