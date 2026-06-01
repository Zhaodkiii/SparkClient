import SwiftUI

struct MedicalValidationIssueBadge: View {
    var body: some View {
        Text(L10n.text("medical.upload.presubmit.badge.needs_fix"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            )
    }
}

struct MedicalValidationIssueInlineView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MedicalValidatedResultInfoLine: View {
    let title: String
    let value: String
    let issues: [MedicalPreSubmitValidationIssue]

    private var displayValue: String {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, issues.isEmpty == false {
            return L10n.text("medical.upload.presubmit.value.not_filled")
        }
        return value.isEmpty ? "-" : value
    }

    @ViewBuilder
    var body: some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayValue)
                .font(.body)
                .foregroundStyle(issues.isEmpty ? Color.primary : Color.red)
                .textSelection(.enabled)
            if let message = issues.first?.message {
                MedicalValidationIssueInlineView(message: message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let anchorID = issues.first?.scrollTargetID {
            content.id(anchorID)
        } else {
            content
        }
    }
}

struct MedicalValidationCardChrome: ViewModifier {
    let hasError: Bool
    var scrollTargetID: String?

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(hasError ? Color.red.opacity(0.45) : Color.clear, lineWidth: hasError ? 2 : 0)
            )
            .id(scrollTargetID)
    }
}

extension View {
    func medicalValidationCardChrome(hasError: Bool, scrollTargetID: String? = nil) -> some View {
        modifier(MedicalValidationCardChrome(hasError: hasError, scrollTargetID: scrollTargetID))
    }
}
