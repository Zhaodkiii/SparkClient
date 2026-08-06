import SwiftUI

struct DeepTutorQuizParseErrorCardView: View {
    let payload: DeepTutorQuizParseErrorPayload
    let onRegenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(payload.title)
                    .font(.headline)
            }

            Text(payload.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("重新生成", action: onRegenerate)
                .buttonStyle(.borderedProminent)

            #if DEBUG
            Text("解析失败原因：\(payload.reason)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("messageID: \(payload.messageID.uuidString.prefix(8))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            #endif
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}
