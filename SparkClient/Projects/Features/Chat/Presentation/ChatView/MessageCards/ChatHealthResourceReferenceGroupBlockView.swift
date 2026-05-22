import SwiftUI

/// 用户消息内多份 `health_resource_reference` 汇总展示：纵向列表，≥3 份时限制高度并可滚动。
struct ChatHealthResourceReferenceGroupBlockView: View {
    let payloads: [ChatHealthResourceReferencePayload]
    let medicalQueryAPI: SparkMedicalQueryAPI
    let cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let onUnavailableTap: () -> Void
    let destinationBuilder: (HealthResourceReference) -> AnyView

    private var totalRefs: Int { max(1, payloads.count) }
    /// 三份以内不滚动；三份及以上在固定高度内滚动。
    private var isScrollable: Bool { payloads.count >= 3 }

    var body: some View {
        ConditionalVerticalScroll(
            isScrollable: isScrollable,
            showsIndicators: isScrollable
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(payloads, id: \.listIdentity) { payload in
                    ChatHealthResourceReferenceBlockView(
                        payload: payload,
                        totalRefs: totalRefs,
                        medicalQueryAPI: medicalQueryAPI,
                        cachedCompleteData: cachedCompleteData,
                        onUnavailableTap: onUnavailableTap,
                        destinationBuilder: destinationBuilder
                    )
                }
            }
        }
    }
}


private extension ChatHealthResourceReferencePayload {
    var listIdentity: String {
        "\(resourceType):\(resourceId):\(memberId):\(refIndex)"
    }
}
