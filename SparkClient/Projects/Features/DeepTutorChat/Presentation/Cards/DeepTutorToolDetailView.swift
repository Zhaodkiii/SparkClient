import SwiftUI

struct DeepTutorToolDetailView: View {
    let toolName: String
    let argsDetail: String?
    let resultDetail: String?
    let resultIsMarkdown: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let argsDetail, argsDetail.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("→")
                                .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.5))
                            Text(toolName)
                                .font(.system(size: DeepTutorPalette.traceDetailFontSize))
                                .foregroundStyle(DeepTutorPalette.traceMutedText)
                        }
                        Text(argsDetail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DeepTutorPalette.traceMutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(DeepTutorPalette.mutedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.leading, 12)
                    }
                }

                if let resultDetail, resultDetail.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("✓")
                                .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.5))
                            Text(toolName)
                                .font(.system(size: DeepTutorPalette.traceDetailFontSize))
                                .foregroundStyle(DeepTutorPalette.traceMutedText)
                        }
                        Group {
                            if resultIsMarkdown {
                                DeepTutorMarkdownRenderer(markdown: resultDetail)
                                    .font(.system(size: DeepTutorPalette.traceBodyFontSize))
                            } else {
                                Text(resultDetail)
                                    .font(.system(size: DeepTutorPalette.traceBodyFontSize))
                            }
                        }
                        .foregroundStyle(DeepTutorPalette.traceMutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                    }
                }
            }
            .font(.system(size: DeepTutorPalette.traceDetailFontSize))
            .foregroundStyle(DeepTutorPalette.traceMutedText)
            .lineSpacing(4)
        }
        .frame(maxHeight: 260, alignment: .top)
    }
}
