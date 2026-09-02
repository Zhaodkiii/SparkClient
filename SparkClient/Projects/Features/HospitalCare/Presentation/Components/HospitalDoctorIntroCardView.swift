import SwiftUI

nonisolated struct HospitalDoctorIntroCardPayload: Codable, Equatable, Sendable {
    struct DoctorSnapshot: Codable, Equatable, Sendable {
        var displayName: String
        var title: String
        var hospitalName: String
        var departmentName: String
        var avatarUrl: String
    }

    struct AgentSnapshot: Codable, Equatable, Sendable {
        var agentId: UUID
        var agentName: String
        var serviceBoundary: String
    }

    struct DetailRoute: Codable, Equatable, Sendable {
        var agentId: UUID
    }

    var doctor: DoctorSnapshot
    var agent: AgentSnapshot
    var professionalDirections: [String]
    var introductionExcerpt: String
    var detailRoute: DetailRoute
}

struct HospitalDoctorIntroCardView: View {
    let payload: HospitalDoctorIntroCardPayload

    var body: some View {
        NavigationLink {
            DoctorLightProfileView(
                agentID: payload.detailRoute.agentId,
                hospitalName: payload.doctor.hospitalName,
                consultActionTitle: "咨询医生智能体",
                onConsult: {}
            )
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .accessibilityLabel("医生智能体简介，\(payload.doctor.displayName)，\(payload.doctor.title) \(payload.doctor.departmentName)")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(payload.doctor.displayName)
                            .font(.headline)
                        Spacer(minLength: 8)
                        Text("医生智能体")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    Text([payload.doctor.title, payload.doctor.departmentName].filter { $0.isEmpty == false }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(payload.doctor.hospitalName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if payload.professionalDirections.isEmpty == false {
                Text(payload.professionalDirections.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if payload.introductionExcerpt.isEmpty == false {
                Text(payload.introductionExcerpt)
                    .font(.footnote)
                    .lineLimit(2)
            }
            if payload.agent.serviceBoundary.isEmpty == false {
                Text(payload.agent.serviceBoundary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("查看医生简介")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = URL(string: payload.doctor.avatarUrl), payload.doctor.avatarUrl.isEmpty == false {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.16))
            .frame(width: 48, height: 48)
            .overlay {
                Text(String(payload.doctor.displayName.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
    }
}
