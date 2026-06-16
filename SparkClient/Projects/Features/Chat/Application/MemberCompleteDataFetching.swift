import Foundation

/// 成员 complete-data 拉取：用协议注入替代 async closure，避免 iOS 16 回部署时 View 元数据崩溃。
@MainActor
protocol MemberCompleteDataFetching: AnyObject {
    func fetchMemberCompleteData(memberID: Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData
}
