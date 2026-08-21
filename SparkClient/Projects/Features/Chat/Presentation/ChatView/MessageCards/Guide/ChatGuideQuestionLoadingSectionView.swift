import SwiftUI

/// 引导卡片问题区 loading 行（生成中不可点击）。
struct ChatGuideQuestionLoadingRowView: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

/// 引导卡片问题区 loading skeleton（3 行占位）。
struct ChatGuideQuestionLoadingSectionView: View {
    let loadingTitle: String

    var body: some View {
        VStack(spacing: 12) {
            ChatGuideQuestionLoadingRowView(
                title: loadingTitle
            )
            .redacted(reason: [])
            .allowsHitTesting(false)
//            ForEach(0..<3, id: \.self) { index in
//                ChatGuideQuestionLoadingRowView(
//                    title: index == 0 ? loadingTitle : " "
//                )
//                .redacted(reason: index == 0 ? [] : .placeholder)
//                .allowsHitTesting(false)
//            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(loadingTitle)
    }
}
