import SwiftUI

struct MedicationExecutionDoseDetailSheet: View {
    let dose: MedicationExecutionDose
    let dayStart: Date
    @Binding var edit: MedicationExecutionDoseEdit
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var tempQuantity: Double
    @State private var isDosePickerExpanded = false
    @State private var isTimePickerExpanded = false
    @State private var tempScheduledAt: Date

    private let calendar = Calendar.current
    private let quantityOptions = MedicationExecutionDoseEditSupport.quantityOptions
    private static let sheetHeaderChromeHeight: CGFloat = 72
    private static let sheetMinimumHeight: CGFloat = 350

    init(
        dose: MedicationExecutionDose,
        dayStart: Date,
        edit: Binding<MedicationExecutionDoseEdit>,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.dose = dose
        self.dayStart = dayStart
        self._edit = edit
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _tempQuantity = State(initialValue: edit.wrappedValue.quantity)
        _tempScheduledAt = State(initialValue: edit.wrappedValue.scheduledAt)
    }

    private var doseValueText: String {
        MedicationExecutionDoseEditSupport.formattedDose(
            quantity: tempQuantity,
            unit: edit.doseUnit
        )
    }

    private var timeValueText: String {
        MedicationExecutionPlanner.timeText(for: tempScheduledAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            AdaptiveToolSheetScrollView(
                bottomContentPadding: 32,
                extraChromeHeight: Self.sheetHeaderChromeHeight,
                minimumHeight: Self.sheetMinimumHeight
            ) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dose.displayName)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(dose.detailSubtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 16) {
                        doseCard
                        timeCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private var headerBar: some View {
        ZStack {
            Text(L10n.text("home.medical.medication_execution.detail.title"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("common.close"))

                Spacer()

                Button(action: confirm) {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .systemBlue), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("common.done"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var doseCard: some View {
        VStack(spacing: 0) {
            detailRow(
                title: dose.dosageFormLabel,
                value: doseValueText,
                isExpanded: isDosePickerExpanded
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isDosePickerExpanded.toggle()
                    if isDosePickerExpanded {
                        isTimePickerExpanded = false
                    }
                }
            }

            if isDosePickerExpanded {
                Picker("", selection: $tempQuantity) {
                    ForEach(quantityOptions, id: \.self) { value in
                        Text(
                            MedicationExecutionDoseEditSupport.formattedDose(
                                quantity: value,
                                unit: edit.doseUnit
                            )
                        )
                        .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var timeCard: some View {
        VStack(spacing: 0) {
            detailRow(
                title: L10n.text("home.medical.medication_execution.detail.time"),
                value: timeValueText,
                isExpanded: isTimePickerExpanded
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isTimePickerExpanded.toggle()
                    if isTimePickerExpanded {
                        isDosePickerExpanded = false
                    }
                }
            }

            if isTimePickerExpanded {
                DatePicker(
                    "",
                    selection: $tempScheduledAt,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func detailRow(
        title: String,
        value: String,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(value)
        .accessibilityHint(
            isExpanded
                ? L10n.text("home.medical.medication_execution.detail.collapse")
                : L10n.text("home.medical.medication_execution.detail.expand")
        )
    }

    private func confirm() {
        edit.quantity = tempQuantity
        edit.scheduledAt = MedicationExecutionDoseEditSupport.mergeTime(
            tempScheduledAt,
            on: dayStart,
            calendar: calendar
        )
        MedicationExecutionSupport.impact(style: .light)
        onConfirm()
    }
}
