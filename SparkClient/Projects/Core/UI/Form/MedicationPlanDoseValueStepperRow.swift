import SwiftUI
import UIKit

/// 用药计划表单中的剂量数值行：标题 + 步进控件。
/// 默认使用系统 `Stepper`；可通过 `controlStyle: .custom` 切换为自定义加减与文本输入。
struct MedicationPlanDoseValueStepperRow: View {
    enum ControlStyle {
        case systemStepper
        case custom
    }

    @Binding var text: String
    var keyboardVisible: Binding<Bool>?
    var controlStyle: ControlStyle = .systemStepper
    var title: String = L10n.text("medication_plan.form.dose_value", fallback: "剂量数值")
    var minValue: Double = 0
    var maxValue: Double = 9999
    var step: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            switch controlStyle {
            case .systemStepper:
                systemStepper
            case .custom:
                MedicationPlanDoseValueCustomStepperControls(
                    text: $text,
                    keyboardVisible: keyboardVisible,
                    minValue: minValue,
                    maxValue: maxValue,
                    step: step
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

    }

    private var systemStepper: some View {
        Stepper(
            stepperLabel,
            value: numericBinding,
            in: minValue...maxValue,
            step: step
        )
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
    }

    private var stepperLabel: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Self.formatDose(minValue)
        }
        return trimmed
    }

    private var numericBinding: Binding<Double> {
        Binding(
            get: {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false, let value = Double(trimmed) else {
                    return minValue
                }
                return min(max(value, minValue), maxValue)
            },
            set: { newValue in
                let clamped = min(max(newValue, minValue), maxValue)
                text = Self.formatDose(clamped)
            }
        )
    }

    private static func formatDose(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }
}

// MARK: - Custom +/- controls

private struct MedicationPlanDoseValueCustomStepperControls: View {
    @Binding var text: String
    var keyboardVisible: Binding<Bool>?
    var minValue: Double
    var maxValue: Double
    var step: Double

    @FocusState private var isValueFocused: Bool

    private var controlFill: Color { Color(uiColor: .systemPurple).opacity(0.12) }
    private var controlStroke: Color { Color(uiColor: .systemPurple).opacity(0.35) }
    private var accentColor: Color { Color(uiColor: .systemPurple) }

    private var numericValue: Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let value = Double(trimmed) else { return 0 }
        return value
    }

    private var canDecrement: Bool {
        numericValue > minValue + 1e-9
    }

    private var canIncrement: Bool {
        numericValue < maxValue - 1e-9
    }

    var body: some View {
        HStack(spacing: 12) {
            decrementButton
            valueField
            incrementButton
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text)
        .onChange(of: isValueFocused) { focused in
            keyboardVisible?.wrappedValue = focused
        }
    }

    private var decrementButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmed), trimmed.isEmpty == false else { return }
            text = formatDose(max(minValue, value - step))
        } label: {
            Image(systemName: "minus")
                .font(.headline.weight(.semibold))
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .frame(width: 32, height: 32)
                .background(controlFill, in: Circle())
                .overlay(Circle().strokeBorder(controlStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(canDecrement == false)
        .opacity(canDecrement ? 1 : 0.45)
        .accessibilityLabel(L10n.text("medication_plan.form.dose_decrement", fallback: "减少剂量"))
    }

    private var incrementButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                text = formatDose(step)
                return
            }
            let value = Double(trimmed) ?? minValue
            text = formatDose(min(maxValue, max(minValue, value) + step))
        } label: {
            Image(systemName: "plus")
                .font(.headline.weight(.bold))
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(accentColor, in: Circle())
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(canIncrement == false)
        .opacity(canIncrement ? 1 : 0.45)
        .accessibilityLabel(L10n.text("medication_plan.form.dose_increment", fallback: "增加剂量"))
    }

    private var valueField: some View {
        TextField(
            L10n.text("medication_plan.form.dose_value_placeholder", fallback: "如 1"),
            text: $text
        )
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .focused($isValueFocused)
        .keyboardType(.decimalPad)
        .font(.title3.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity)
        .sparkKeyboardDoneToolbar {
                    SparkKeyboardDismiss.endEditing()
                }
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        )
    }

    private func formatDose(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }
}
