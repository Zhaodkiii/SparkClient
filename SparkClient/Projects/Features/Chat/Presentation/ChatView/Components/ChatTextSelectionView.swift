import SwiftUI
import UIKit

// MARK: - 可选文本 UITextView（支持全选）

private struct ChatSelectableTextView: UIViewRepresentable {
    let text: String
    @Binding var shouldSelectAll: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.text = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textColor = UIColor.label
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        if shouldSelectAll {
            uiView.selectAll(nil)
            let binding = _shouldSelectAll
            DispatchQueue.main.async {
                binding.wrappedValue = false
            }
        }
    }
}

// MARK: - 选择文本（复制 / 全选 / 存为知识）

struct ChatTextSelectionView: View {
    let text: String
    var onSaveToKnowledge: (() -> Void)?

    @State private var isCopy = false
    @State private var shouldSelectAll = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ChatSelectableTextView(text: text, shouldSelectAll: $shouldSelectAll)

            HStack(spacing: 12) {
                floatingButton(systemName: "character.cursor.ibeam", tint: .accentColor) {
                    shouldSelectAll = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                if let onSaveToKnowledge {
                    floatingButton(systemName: "backpack", tint: .accentColor) {
                        onSaveToKnowledge()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                floatingButton(
                    systemName: isCopy ? "checkmark" : "square.on.square",
                    tint: isCopy ? .green : .accentColor
                ) {
                    UIPasteboard.general.string = text
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isCopy = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { isCopy = false }
                    }
                }
            }
            .padding()
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func floatingButton(
        systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
