import SwiftUI

/// 第三页：选择日期与本地演示号源。
struct HospitalRegistrationScheduleView: View {
    let selection: RegistrationSelection
    @ObservedObject var viewModel: HospitalRegistrationDemoViewModel
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selection.displayTitle).font(.title3.bold())
                    Text("请选择预约日期和到院时段").font(.subheadline).foregroundStyle(.secondary)
                }
                datePicker
                Text("可预约时段").font(.headline)
                ForEach(viewModel.slots(for: selection.type)) { slot in
                    NavigationLink {
                        HospitalRegistrationConfirmationView(
                            selection: selection.with(date: viewModel.selectedDate, slot: slot),
                            viewModel: viewModel,
                            onFinish: onFinish
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text(slot.time).font(.headline).foregroundStyle(.primary); Text(slot.period).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text("¥ \(Int(selection.fee))").foregroundStyle(.orange)
                            Text("余\(slot.remaining)/总\(slot.total)").font(.caption.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 6).background(.green, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("确认挂号时间")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var datePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.days) { day in
                    Button { viewModel.selectedDate = day.date } label: {
                        VStack(spacing: 6) { Text(day.weekday).font(.caption); Text(day.day).font(.headline); Text("有号").font(.caption.weight(.semibold)) }
                            .foregroundStyle(Calendar.current.isDate(day.date, inSameDayAs: viewModel.selectedDate) ? .white : .primary)
                            .frame(width: 64, height: 76)
                            .background(Calendar.current.isDate(day.date, inSameDayAs: viewModel.selectedDate) ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private extension RegistrationSelection {
    func with(date: Date, slot: RegistrationSlot) -> RegistrationSelection {
        var copy = self; copy.date = date; copy.slot = slot; return copy
    }
}
