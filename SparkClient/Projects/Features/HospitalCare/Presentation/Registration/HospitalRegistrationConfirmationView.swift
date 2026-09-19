import SwiftUI

/// 第四页：预约信息确认；下一步只进入本地成功结果页。
struct HospitalRegistrationConfirmationView: View {
    let selection: RegistrationSelection
    @ObservedObject var viewModel: HospitalRegistrationDemoViewModel
    let onFinish: () -> Void
    @State private var agreed = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let member = viewModel.memberContextStore.context.selectedMember {
                    HStack {
                        Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) { Text(member.name).font(.headline); Text("当前就诊人").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                    }
                    .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(spacing: 0) {
                    detailRow("就诊医院", viewModel.hospital?.name ?? "")
                    detailRow("就诊科室", selection.department.name)
                    if let doctor = selection.doctor { detailRow("预约医生", doctor.doctorDisplayName) }
                    detailRow("预约时间", appointmentText)
                    detailRow("挂号级别", selection.type.title)
                    detailRow("挂号费用", String(format: "¥ %.2f", selection.fee), emphasized: true)
                }
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Toggle("我已仔细阅读并了解《挂号须知》", isOn: $agreed).tint(Color.accentColor)
                NavigationLink {
                    HospitalRegistrationResultView(selection: selection, viewModel: viewModel, onFinish: onFinish)
                } label: {
                    Text("确认预约（演示）").frame(maxWidth: .infinity)
                }
                    .buttonStyle(.borderedProminent).tint(Color.accentColor).controlSize(.large).disabled(!agreed)
                Text("演示模式：本次操作不会向医院后台提交预约。").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("预约挂号确认")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appointmentText: String { "\(selection.date.formatted(.dateTime.year().month().day().weekday(.wide))) \(selection.slot?.time ?? "")" }

    private func detailRow(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .top) { Text(title).foregroundStyle(.secondary); Spacer(minLength: 24); Text(value).multilineTextAlignment(.trailing).foregroundStyle(emphasized ? .orange : .primary) }
            .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
