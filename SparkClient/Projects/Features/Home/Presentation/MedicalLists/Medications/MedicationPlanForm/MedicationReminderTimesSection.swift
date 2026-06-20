import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum MedicationReminderTimePickerRoute: Identifiable {
    case add
    case edit(index: Int)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let index):
            return "edit_\(index)"
        }
    }
}

private struct MedicationReminderTimePickerSheet: View {
    @Binding var selectedTime: Date
    let onConfirm: () -> Void
    @State private var tempTime: Date

    init(selectedTime: Binding<Date>, onConfirm: @escaping () -> Void) {
        self._selectedTime = selectedTime
        self.onConfirm = onConfirm
        self._tempTime = State(initialValue: selectedTime.wrappedValue)
    }

    var body: some View {
        AdaptiveSheetContainer.fixed(
            height: 260,
            onCancel: {},
            onConfirm: {
                selectedTime = tempTime
                onConfirm()
            }
        ) {
            DatePicker(
                "",
                selection: $tempTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct MedicationReminderTimesSection: View {
    @Binding var draft: MedicationPlanDraft
    let notificationClient: any NotificationClient

    @State private var timePickerRoute: MedicationReminderTimePickerRoute?
    @State private var timePickerSelection = Date()

    private var slots: [String] {
        draft.orderedReminderTimeSlots
    }

    private var countSubtitle: String {
        let n = slots.count
        return String(format: L10n.text("medication_plan.form.reminder_times.count_per_day", fallback: "%d times/day"), locale: .current, n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("medication_plan.form.field.medication_times", fallback: "用药时间"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 12)
                Text(countSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        timePickerSelection = defaultTimeForNewSlot()
                        timePickerRoute = .add
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 40, height: 40)
                            .background(Color(uiColor: .systemBackground), in: Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("medication_plan.form.a11y.add_medication_time", fallback: "新增用药时间"))

                    ForEach(Array(slots.enumerated()), id: \.offset) { index, time in
                        Menu {
                            Button {
                                timePickerSelection = MedicationPlanDraft.dateForReminderTimeToken(time)
                                timePickerRoute = .edit(index: index)
                            } label: {
                                Label(L10n.text("common.edit"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                removeSlot(at: index)
                            } label: {
                                Label(L10n.text("common.delete"), systemImage: "trash")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(time)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .systemBackground), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                            )
                        }
                        .accessibilityLabel(String(format: L10n.text("medication_plan.form.a11y.medication_time_format", fallback: "Medication time %@"), locale: .current, time))
                    }
                }
                .padding(.vertical, 2)
            }

            if let reminderTimesError = draft.reminderTimesError {
                Text(reminderTimesError)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
        .sheet(item: $timePickerRoute) { route in
            MedicationReminderTimePickerSheet(selectedTime: $timePickerSelection) {
                applyPickedTime(route: route)
            }
        }
    }

    private func defaultTimeForNewSlot() -> Date {
        if let last = slots.last {
            return MedicationPlanDraft.dateForReminderTimeToken(last)
        }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 8
        c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    private func applyPickedTime(route: MedicationReminderTimePickerRoute) {
        let picked = MedicationPlanDraft.reminderTimeString(from: timePickerSelection)
        guard MedicationPlanDraft.isValidTimeText(picked) else { return }

        var next = slots
        switch route {
        case .add:
            if next.contains(picked) {
                notificationClient.warning(
                    L10n.text("medication_plan.form.reminder_times.duplicate", fallback: "该提醒时间已存在"),
                    source: "medication.plan.reminder_times"
                )
                return
            }
            next.append(picked)
        case .edit(let index):
            guard next.indices.contains(index) else { return }
            if let dup = next.firstIndex(of: picked), dup != index {
                notificationClient.warning(
                    L10n.text("medication_plan.form.reminder_times.duplicate", fallback: "该提醒时间已存在"),
                    source: "medication.plan.reminder_times"
                )
                return
            }
            next[index] = picked
        }
        draft.replaceReminderTimeSlots(next)
    }

    private func removeSlot(at index: Int) {
        var next = slots
        guard next.indices.contains(index) else { return }
        next.remove(at: index)
        draft.replaceReminderTimeSlots(next)
    }
}
