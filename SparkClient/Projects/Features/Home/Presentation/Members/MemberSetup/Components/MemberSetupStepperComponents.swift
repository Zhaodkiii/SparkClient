import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MemberSetupHeroView: View {
    let systemImage: String
    let accentColor: UIColor

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Color(accentColor))
                .frame(width: 120, height: 120)
                .background(Color(accentColor).opacity(0.12), in: Circle())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MemberSetupStepperCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.bold))
                        .imageScale(.medium)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
                Text(title)
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
    }
}

struct MemberSetupStepperFieldLabel: View {
    let title: String
    var required = false

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

struct MemberSetupStepperTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var required = false
    var keyboardVisible: Binding<Bool>?

    @FocusState private var isFocused: Bool

    private var isInvalid: Bool {
        required && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MemberSetupStepperFieldLabel(title: title, required: required)

            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.words)
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

extension View {
    func memberSetupFlowDismissToolbar(onDismiss: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}
