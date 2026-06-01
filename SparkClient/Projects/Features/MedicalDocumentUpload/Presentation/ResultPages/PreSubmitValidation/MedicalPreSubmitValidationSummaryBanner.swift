import SwiftUI

struct MedicalPreSubmitValidationSummaryBanner: View {
    let issues: [MedicalPreSubmitValidationIssue]
    var onSelectIssue: ((MedicalPreSubmitValidationIssue) -> Void)?

    private var blockingIssues: [MedicalPreSubmitValidationIssue] {
        issues.blockingIssues
    }

    var body: some View {
        if blockingIssues.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    String(
                        format: L10n.text("medical.upload.presubmit.summary.title"),
                        blockingIssues.count
                    )
                )
                .font(.headline.weight(.semibold))
                .foregroundStyle(.red)

                Text(L10n.text("medical.upload.presubmit.summary.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(blockingIssues.prefix(5).enumerated()), id: \.element.id) { index, issue in
                        Button {
                            onSelectIssue?(issue)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                                Text(issue.summaryLine)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
            )
        }
    }
}
