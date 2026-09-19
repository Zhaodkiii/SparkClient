import SwiftUI

/// 第五页：预约成功结果，仅展示本地生成的演示信息。
struct HospitalRegistrationResultView: View {
    let selection: RegistrationSelection
    @ObservedObject var viewModel: HospitalRegistrationDemoViewModel
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green).padding(.top, 30)
                Text("预约成功").font(.title.bold())
                Text("演示预约结果，未产生真实挂号记录").font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    detailRow("就诊人", viewModel.memberContextStore.context.selectedMember?.name ?? "未选择")
                    detailRow("就诊医院", viewModel.hospital?.name ?? "")
                    detailRow("就诊科室", selection.department.name)
                    if let doctor = selection.doctor { detailRow("预约医生", doctor.doctorDisplayName) }
                    detailRow("预约日期", selection.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                    detailRow("预约时间", selection.slot?.time ?? "")
                    detailRow("挂号级别", selection.type.title)
                    detailRow("诊查费用", String(format: "¥ %.2f", selection.fee), emphasized: true)
                }
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("完成", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .controlSize(.large)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("预约结果")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private func detailRow(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .top) { Text(title).foregroundStyle(.secondary); Spacer(minLength: 24); Text(value).multilineTextAlignment(.trailing).foregroundStyle(emphasized ? .orange : .primary) }
            .padding(.horizontal, 16).padding(.vertical, 14)
    }
}
