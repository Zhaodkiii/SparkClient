import SwiftUI

struct DoctorLightProfileView: View {
    let agentID: UUID
    let hospitalName: String
    let consultActionTitle: String
    let onConsult: () -> Void
    /// 用于命中账号级医院目录缓存；缺省 nil 时直接回源。
    var accountID: Int64? = nil

    @Environment(\.hospitalCare) private var hospitalCare
    @Environment(\.dismiss) private var dismiss
    @State private var profile: HospitalDoctorLightProfile?
    @State private var errorText: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("正在加载医生简介…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let errorText {
                    Text(errorText)
                        .foregroundStyle(.secondary)
                } else if let profile {
                    identity(profile)
                    // CHAT-000054：所在医院区块；介绍为空时只显示名称，不渲染空介绍区块。
                    let resolvedHospitalName = profile.hospitalName.isEmpty ? hospitalName : profile.hospitalName
                    if resolvedHospitalName.isEmpty == false {
                        section(title: "所在医院") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(resolvedHospitalName)
                                    .font(.subheadline.weight(.medium))
                                if profile.hospitalIntroduction.isEmpty == false {
                                    Text(profile.hospitalIntroduction)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if profile.specialties.isEmpty == false {
                        section(title: "擅长方向") {
                            FlowSpecialtyChips(items: profile.specialties)
                        }
                    }
                    if profile.introduction.isEmpty == false {
                        section(title: "医生简介") {
                            Text(profile.introduction)
                                .font(.body)
                        }
                    }
                    if profile.serviceBoundary.isEmpty == false {
                        section(title: "AI 助手说明") {
                            Text(profile.serviceBoundary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("医生简介")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(consultActionTitle) {
                onConsult()
                dismiss()
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .task {
            await load()
        }
    }

    private func identity(_ profile: HospitalDoctorLightProfile) -> some View {
        HStack(alignment: .top, spacing: 14) {
            avatar(profile)
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.displayName)
                    .font(.title2.weight(.semibold))
                Text([profile.title, profile.departmentName].filter { $0.isEmpty == false }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                Text(profile.hospitalName.isEmpty ? hospitalName : profile.hospitalName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("医生智能体 · \(profile.agentName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func avatar(_ profile: HospitalDoctorLightProfile) -> some View {
        HospitalAvatarImageView(
            urlString: profile.avatarURL,
            size: 72,
            placeholderText: String(profile.displayName.prefix(1))
        )
    }

    private func load() async {
        guard let hospitalCare else {
            errorText = "医院服务未就绪"
            isLoading = false
            return
        }
        isLoading = true
        do {
            profile = try await hospitalCare.loadDoctorProfile.execute(
                agentID: agentID,
                accountID: accountID,
                hospitalName: hospitalName
            )
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

private struct FlowSpecialtyChips: View {
    let items: [String]

    var body: some View {
        FlexibleChipWrap(items: items)
    }
}

private struct FlexibleChipWrap: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}
