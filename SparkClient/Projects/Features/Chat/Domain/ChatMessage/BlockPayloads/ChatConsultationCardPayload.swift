import Foundation

/// 线上问诊消息卡片负载（与 ``HospitalConsultationDTO`` 同构，供 Chat block 解码）。
typealias ChatConsultationCardPayload = HospitalConsultationDTO

extension HospitalConsultationDTO {
    /// 问诊详情页 / Sheet 复用同一 DTO。
    var asConsultationDetailModel: HospitalConsultationDTO { self }
}
