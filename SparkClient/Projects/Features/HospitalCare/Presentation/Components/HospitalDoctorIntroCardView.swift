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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(payload.doctor.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        aiBadge
                    }
                    Text([payload.doctor.title, payload.doctor.departmentName].filter { $0.isEmpty == false }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(payload.doctor.hospitalName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 28)

            if payload.professionalDirections.isEmpty == false {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "heart.text.square")
                        .font(.title2)
                        .fontWeight(.medium)
                        .imageScale(.medium)
                        .foregroundStyle(accent)
                    Text(payload.professionalDirections.joined(separator: " · "))
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 24)
            }

            if payload.introductionExcerpt.isEmpty == false {
                Text(payload.introductionExcerpt)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .overlay(alignment: .top) { divider }
            }

            if payload.agent.serviceBoundary.isEmpty == false {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title3)
                        .fontWeight(.medium)
                        .imageScale(.medium)
                        .foregroundStyle(accent)
                    Text("由\(payload.doctor.displayName)团队维护")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 20)
                .overlay(alignment: .top) { divider }

//                HStack(alignment: .top, spacing: 14) {
//                    Image(systemName: "info.circle")
//                        .font(.title3)
//                        .imageScale(.medium)
//                        .foregroundStyle(.secondary)
//                    Text(payload.agent.serviceBoundary)
//                        .font(.callout)
//                        .foregroundStyle(.secondary)
//                        .lineSpacing(3)
//                        .fixedSize(horizontal: false, vertical: true)
//                }
//                .padding(.top, 20)
//                .padding(.bottom, 18)
            }

            detailButton
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var accent: Color {
        Color(uiColor: .systemTeal)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.65))
            .frame(height: 1)
    }

    private var aiBadge: some View {
        Label("AI 助手", systemImage: "bubbles.and.sparkles.fill")
            .font(.caption)
            .fontWeight(.semibold)
            .imageScale(.small)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(accent, in: Capsule())
            .fixedSize()
    }

    private var detailButton: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .fontWeight(.medium)
                .imageScale(.medium)
                .foregroundStyle(accent)
            Text("查看医生简介")
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.body)
                .fontWeight(.semibold)
                .imageScale(.small)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = URL(string: payload.doctor.avatarUrl), payload.doctor.avatarUrl.isEmpty == false {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty, .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(accent.opacity(0.12))
            .frame(width: 120, height: 120)
            .overlay {
                Text(doctorSurname)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(accent)
            }
    }

    private var doctorSurname: String {
        let name = payload.doctor.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastNameToken = name.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? name
        return lastNameToken.first.map { String($0) } ?? "医"
    }
}
