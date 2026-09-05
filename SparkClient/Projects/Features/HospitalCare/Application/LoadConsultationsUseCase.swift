import Foundation

/// 最近问诊列表加载用例（DOCTOR-WORKSPACE-000004 页面形态修订）。
///
/// 数据源仅为患者已提交的线上问诊单；memberID 为空时返回当前账号全部成员的问诊。
nonisolated struct LoadConsultationsUseCase: Sendable {
    let remoteAPI: any HospitalCareRemoteServing

    func execute(memberID: Int?) async throws -> [HospitalConsultationDTO] {
        try await remoteAPI.listConsultations(memberID: memberID, page: 1, pageSize: 50)
    }
}
