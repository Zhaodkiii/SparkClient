import SwiftUI

struct DeepTutorComposerView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var capability: DeepTutorCapability
    let modelName: String?
    let hasMessages: Bool
    let isStreaming: Bool
    let attachments: [DeepTutorAttachment]
    let references: [DeepTutorContextReference]
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)

            DeepTutorComposerCardView(
                text: $text,
                isFocused: $isFocused,
                capability: $capability,
                modelName: modelName,
                hasMessages: hasMessages,
                isStreaming: isStreaming,
                attachments: attachments,
                references: references,
                onSend: onSend,
                onStop: onStop
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground).opacity(0.96))
    }
}
