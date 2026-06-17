import SwiftUI
import UIKit

struct MedicationPlanStepperCard<Content: View>: View {
    let title: String
    var systemImage: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil ,systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
//                        .font(.headline)
                        .font(.title2.weight(.bold))
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                Text(title)
                //                    .font(.headline.weight(.semibold))
                //                    .foregroundStyle(.primary)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                

            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            
            content
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
//        .padding(20)
//        .background(
//            RoundedRectangle(cornerRadius: 16, style: .continuous)
//                .fill(Color(uiColor: .systemBackground))
//        )
//        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

struct MedicationPlanStepperTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var required = false
    var keyboardVisible: Binding<Bool>?
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    private var isInvalid: Bool {
        required && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedicationPlanStepperFieldLabel(title: title, required: required)

            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.primary)
                .keyboardType(keyboardType)
                .focused($isFocused)
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .background(fieldBackground)
                .overlay(fieldBorder)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
                .onChange(of: isFocused) { focused in
                    keyboardVisible?.wrappedValue = focused
                }
        }
        .sparkKeyboardDoneToolbar {
            SparkKeyboardDismiss.endEditing()
            keyboardVisible?.wrappedValue = false
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(borderColor, lineWidth: isFocused || isInvalid ? 1.5 : 0)
    }

    private var borderColor: Color {
        if isInvalid { return Color(uiColor: .systemRed) }
        if isFocused { return Color.accentColor.opacity(0.6) }
        return .clear
    }
}

struct MedicationPlanStepperPickerRow: View {
    let title: String
    let displayValue: String
    let placeholder: String
    var required = false
    var showsValidationError = false
    var onTap: () -> Void

    private var isPlaceholder: Bool {
        displayValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayValue == placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedicationPlanStepperFieldLabel(title: title, required: required)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            } label: {
                HStack(spacing: 12) {
                    Text(isPlaceholder ? placeholder : displayValue)
                        .font(.body)
                        .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .imageScale(.small)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(showsValidationError ? Color(uiColor: .systemRed) : .clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct MedicationPlanStepperTextArea: View {
    let title: String
    @Binding var text: String
    var placeholder: String
    var keyboardVisible: Binding<Bool>?
    var minHeight: CGFloat = 128

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedicationPlanStepperFieldLabel(title: title, required: false)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .focused($isFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: minHeight)
                    .background(Color.clear)
            }
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
            .onChange(of: isFocused) { focused in
                keyboardVisible?.wrappedValue = focused
            }
        }
        .sparkKeyboardDoneToolbar {
            SparkKeyboardDismiss.endEditing()
            keyboardVisible?.wrappedValue = false
        }
    }
}

struct MedicationPlanStepperBottomBar: View {
    let canSubmit: Bool
    var backTitle: String?
    let primaryTitle: String
    var primarySystemImage: String?
    var keyboardVisible: Binding<Bool>?
    var onBack: () -> Void
    var onPrimary: () -> Void

    var body: some View {
        Group {
            if keyboardVisible?.wrappedValue == true {
                EmptyView()
            } else {
                bottomButtons
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSubmit)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: keyboardVisible?.wrappedValue == true)
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            Button {
                guard canSubmit else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onPrimary()
            } label: {
                HStack(spacing: 8) {
                    if let primarySystemImage {
                        Image(systemName: primarySystemImage)
                            .imageScale(.medium)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text(primaryTitle)
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(canSubmit ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(primaryBackground)
            }
            .buttonStyle(.plain)
            .disabled(canSubmit == false)
            .shadow(color: Color.black.opacity(canSubmit ? 0.08 : 0), radius: 12, x: 0, y: 4)

            if let backTitle {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onBack()
                } label: {
                    Text(backTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.regularMaterial)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var primaryBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(canSubmit ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray4))
    }

}

struct MedicationPlanStepperFieldLabel: View {
    let title: String
    var required: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            if required {
                Text("*")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemRed))
            }
        }
    }
}

extension View {
    func medicationPlanStepperBottomBar(
        canSubmit: Bool,
        backTitle: String? = nil,
        primaryTitle: String,
        primarySystemImage: String? = nil,
        keyboardVisible: Binding<Bool>?,
        onBack: @escaping () -> Void = {},
        onPrimary: @escaping () -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MedicationPlanStepperBottomBar(
                canSubmit: canSubmit,
                backTitle: backTitle,
                primaryTitle: primaryTitle,
                primarySystemImage: primarySystemImage,
                keyboardVisible: keyboardVisible,
                onBack: onBack,
                onPrimary: onPrimary
            )
        }
    }
}

#Preview("Stepper Components - Light") {
    MedicationPlanStepperComponentsPreview()
        .preferredColorScheme(.light)
}

#Preview("Stepper Components - Dark") {
    MedicationPlanStepperComponentsPreview()
        .preferredColorScheme(.dark)
}

private struct MedicationPlanStepperComponentsPreview: View {
    @State private var name = ""
    @State private var notes = ""
    @State private var keyboardVisible = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MedicationPlanStepperCard(
                        title: L10n.text("medication_plan.stepper.name.card", fallback: "药品信息"),
                        systemImage: "pills.fill"
                    ) {
                        MedicationPlanStepperTextField(
                            title: L10n.text("medication_plan.form.field.drug_name", fallback: "药品名称"),
                            text: $name,
                            placeholder: L10n.text("medication_plan.form.drug_name_placeholder", fallback: "如 阿莫西林胶囊"),
                            required: true,
                            keyboardVisible: $keyboardVisible
                        )

                        MedicationPlanStepperPickerRow(
                            title: L10n.text("medication_plan.stepper.linked_medicine", fallback: "关联药品"),
                            displayValue: "",
                            placeholder: L10n.text("medication_plan.stepper.select_linked_medicine", fallback: "选择药箱药品")
                        ) {}
                    }

                    MedicationPlanStepperTextArea(
                        title: L10n.text("medical_record.forms.field.notes", fallback: "备注"),
                        text: $notes,
                        placeholder: L10n.text("medication_plan.form.instructions_placeholder", fallback: "饭前/饭后、禁忌或医嘱备注"),
                        keyboardVisible: $keyboardVisible
                    )
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.text("medication_plan.stepper.name.nav_title", fallback: "药品名称"))
            .medicationPlanStepperBottomBar(
                canSubmit: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                primaryTitle: L10n.text("common.next", fallback: "下一步"),
                keyboardVisible: $keyboardVisible
            ) {}
        }
    }
}
