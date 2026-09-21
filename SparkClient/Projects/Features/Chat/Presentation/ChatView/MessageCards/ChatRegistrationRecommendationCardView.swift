import SwiftUI

struct ChatRegistrationRecommendationCardView: View {
    let payload: ChatRegistrationRecommendationCardPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("建议挂号")
                        .font(.headline)
                    Text("演示服务 · 不会创建真实预约")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(payload.hospitalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(payload.departmentName)
                    .font(.title3.weight(.semibold))
                if let doctorName = payload.doctorName {
                    Text([doctorName, payload.doctorTitle].compactMap { $0 }.filter { $0.isEmpty == false }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(payload.reasonSummary)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Button {
                NotificationCenter.default.post(
                    name: .chatRegistrationRecommendationTapped,
                    object: payload
                )
            } label: {
                Label(payload.isDoctorSpecific ? "选择日期与时段" : "快速挂号", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("打开演示挂号流程")
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("建议挂号，(payload.hospitalName)，(payload.departmentName)")
    }
}

extension Notification.Name {
    static let chatRegistrationRecommendationTapped = Notification.Name(
        "SparkClient.chatRegistrationRecommendationTapped"
    )
}
