import SwiftUI

struct MedicalDocumentUploadProgressView: View {
    let steps: [MedicalDocumentUploadViewModel.ProgressStep]
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text("处理中")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: step.state))
                            .foregroundStyle(color(for: step.state))
                        Text(step.title)
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func icon(for state: MedicalDocumentUploadViewModel.ProgressStep.State) -> String {
        switch state {
        case .waiting: "circle"
        case .running: "clock.fill"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func color(for state: MedicalDocumentUploadViewModel.ProgressStep.State) -> Color {
        switch state {
        case .waiting: .secondary
        case .running: .blue
        case .done: .green
        case .failed: .red
        }
    }
}
