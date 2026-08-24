import Foundation

/// 首页统一 Sheet 路由
enum HomeSheet: Identifiable {
    case addMember(AddMemberSheet)
    case pendingInvites
    case memberModuleSetup(Member)
    case share(Member)
    case taskCenter
    case apiKeysSettings

    var id: String {
        switch self {
        case .addMember(let sheet):
            return "addMember-\(sheet.id)"
        case .pendingInvites:
            return "pendingInvites"
        case .memberModuleSetup(let member):
            return "memberModuleSetup-\(member.id)"
        case .share(let member):
            return "share-\(member.id)"
        case .taskCenter:
            return "taskCenter"
        case .apiKeysSettings:
            return "apiKeysSettings"
        }
    }
}

/// 首页统一全屏 Cover 路由
enum HomeFullScreenCover: Identifiable, Equatable {
    case medicalDocumentUpload
    case customCamera
    case memberDetail(memberID: Int)
    case chat(threadID: UUID, source: ChatPresentationSource)

    var id: String {
        switch self {
        case .medicalDocumentUpload:
            return "medicalDocumentUpload"
        case .customCamera:
            return "customCamera"
        case .memberDetail(let memberID):
            return "memberDetail-\(memberID)"
        case .chat(let threadID, let source):
            return "chat-\(source.rawValue)-\(threadID.uuidString)"
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
        case .memberModuleSetup:
            self = .memberModuleSetup
        case .share:
            self = .share
        case .taskCenter:
            self = .taskCenter
        case .apiKeysSettings:
            self = .apiKeysSettings
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
        case .memberDetail:
            self = .memberDetail
        case .chat:
            self = .chat
        }
    }
}
