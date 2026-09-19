import SwiftUI

/// 第二页：选择普通号或科室下的专家号。
struct HospitalRegistrationServiceView: View {
    let department: HospitalDepartmentSummary
    @ObservedObject var viewModel: HospitalRegistrationDemoViewModel
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(department.name) · 选择号源").font(.title3.bold())
                    Text("普通号可直接选择时段；专家号来自该科室现有医生数据。").font(.subheadline).foregroundStyle(.secondary)
                }

                NavigationLink {
                    HospitalRegistrationScheduleView(
                        selection: RegistrationSelection(department: department),
                        viewModel: viewModel,
                        onFinish: onFinish
                    )
                } label: {
                    serviceCard(title: "普通号", subtitle: "由门诊医生接诊", price: "¥ 12", icon: "stethoscope")
                }
                .buttonStyle(.plain)

                Text("专家号").font(.headline).padding(.top, 4)
                if viewModel.isLoadingDoctors {
                    ProgressView("正在加载专家医生…").frame(maxWidth: .infinity).padding()
                } else if viewModel.doctors.isEmpty {
                    Text("该科室暂未接入可预约专家，可选择普通号。").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.doctors) { doctor in
                        NavigationLink {
                            HospitalRegistrationScheduleView(
                                selection: RegistrationSelection(department: department, type: .expert, doctor: doctor),
                                viewModel: viewModel,
                                onFinish: onFinish
                            )
                        } label: {
                            doctorCard(doctor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("选择号源")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: department.id) { await viewModel.loadDoctors(for: department) }
    }

    private func serviceCard(title: String, subtitle: String, price: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(); Text(price).font(.headline).foregroundStyle(.orange); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func doctorCard(_ doctor: HospitalAgentCard) -> some View {
        HStack(spacing: 12) {
            HospitalAvatarImageView(urlString: doctor.avatarURL.isEmpty ? doctor.doctorAvatarURL : doctor.avatarURL, size: 52, shape: .roundedSquare(ratio: 0.18), placeholderText: String(doctor.doctorDisplayName.prefix(1)), accent: Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(doctor.doctorDisplayName).font(.headline).foregroundStyle(.primary)
                Text(doctor.doctorTitle.isEmpty ? "专家门诊" : doctor.doctorTitle).font(.subheadline).foregroundStyle(.secondary)
                if doctor.specialties.isEmpty == false { Text("擅长：\(doctor.specialties.joined(separator: "、"))").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) { Text("¥ 22").font(.headline).foregroundStyle(.orange); Text("选择").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
