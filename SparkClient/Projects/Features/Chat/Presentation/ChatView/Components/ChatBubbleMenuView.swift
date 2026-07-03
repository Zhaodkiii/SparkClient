import SwiftUI
import UIKit

// MARK: - Menu Config

/// 消息气泡长按菜单所需的配置（捕获长按那一刻的状态快照）
struct ChatBubbleMenuConfig: Identifiable {
    let id = UUID()
    let message: ChatMessage
    let isAssistant: Bool
    let isSpeaking: Bool
    let isTranslated: Bool
    let plainText: String
    /// 与原始行完全一致的只读气泡视图（showActions=false, allowsHitTesting=false）
    let bubbleView: AnyView
    let hasSelectableText: Bool
    let onCopy: () -> Void
    let onSelectText: (() -> Void)?
    let onDelete: () -> Void
    let onToggleSpeech: (() -> Void)?
    let onToggleTranslate: (() -> Void)?
    let onSaveToKnowledge: (() -> Void)?
}

// MARK: - Menu Styling（对齐 HealthClient MessageMenu.menuButton）

private enum ChatBubbleMenuStyle {
    /// 对应 HealthClient `theme.colors.messageFriendBG`
    static let buttonBackground = Color(uiColor: .secondarySystemGroupedBackground)
    /// 对应 HealthClient `theme.colors.menuText`
    static let buttonForeground = Color.primary
    static let buttonWidth: CGFloat = 208
    static let buttonCornerRadius: CGFloat = 12
    static let buttonVerticalPadding: CGFloat = 11
    static let buttonHorizontalPadding: CGFloat = 12
    static let menuTopPadding: CGFloat = 8
    static let trailingAlignmentInset: CGFloat = 12
}

// MARK: - Menu View

/// 消息气泡长按操作菜单（替代系统 contextMenu）
/// - 背景：ultraThinMaterial + primary.opacity(0.1)，与 HealthClient MessageMenu 一致
/// - 气泡预览：与原始卡片像素级一致
/// - 操作按钮：HealthClient MessageMenu `menuButton` 风格的纵向文字按钮
/// - 滚动：气泡 + 按钮栏整体一起滚动，不单独滚动气泡
struct ChatBubbleMenuView: View {
    let config: ChatBubbleMenuConfig
    let onDismiss: () -> Void

    @State private var appeared = false
    var body: some View {
        // 1. 使用外层 ZStack 统一管理背景和前景内容
        ZStack {
            // --- 背景层 ---
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.primary.opacity(0.1))
            }
            .ignoresSafeArea()
            .contentShape(Rectangle()) // 确保背景完全可点击
            .onTapGesture { dismiss() }
            
            // --- 内容层 ---
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 0)
                        
                        // 原始消息卡片（与列表完全一致，禁止交互）
                        config.bubbleView
                        
                        // HealthClient MessageMenu 风格纵向按钮列表
                        actionMenu
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    // 2. 核心修复：将整个 VStack 的空白区域填充为可点击形状
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97, anchor: .center)
        .onAppear {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                appeared = true
            }
        }
    }

    // MARK: - Action Menu（HealthClient MessageMenu menuButton 风格）

    private var actionMenu: some View {
     
        VStack(spacing: 10) {
            menuButton(
                title: L10n.text("chat.bubble.action.copy"),
                icon: Image(systemName: "doc.on.doc")
            ) {
                config.onCopy()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }

            if config.hasSelectableText {
                menuButton(
                    title: L10n.text("chat.bubble.menu.select_text"),
                    icon: Image(systemName: "text.redaction")
                ) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        config.onSelectText?()
                    }
                }
            }

            if config.isAssistant {
                menuButton(
                    title: config.isTranslated
                        ? L10n.text("chat.bubble.menu.remove_translation")
                        : L10n.text("chat.bubble.menu.translate"),
                    icon: Image(systemName: "character.book.closed")
                ) {
                    config.onToggleTranslate?()
                    dismiss()
                }

                menuButton(
                    title: config.isSpeaking
                        ? L10n.text("chat.bubble.menu.stop_speech")
                        : L10n.text("chat.bubble.menu.speech"),
                    icon: Image(systemName: config.isSpeaking ? "pause.circle" : "waveform")
                ) {
                    config.onToggleSpeech?()
                    dismiss()
                }

                menuButton(
                    title: L10n.text("chat.bubble.knowledge.save"),
                    icon: Image(systemName: "backpack")
                ) {
                    config.onSaveToKnowledge?()
                    dismiss()
                }
            }

            menuButton(
                title: L10n.text("common.delete"),
                icon: Image(systemName: "trash")
            ) {
                config.onDelete()
                dismiss()
            }
        }
        .frame(maxWidth: .infinity, alignment: config.isAssistant ? .leading : .trailing)
        .padding(.top, ChatBubbleMenuStyle.menuTopPadding)
    }

    @ViewBuilder
    private func menuButton(
        title: String,
        icon: Image,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            ZStack {
                ChatBubbleMenuStyle.buttonBackground
                    .cornerRadius(ChatBubbleMenuStyle.buttonCornerRadius)

                HStack {
                    Text(title)
                        .foregroundColor(ChatBubbleMenuStyle.buttonForeground)
                    Spacer()
                    icon
                        .renderingMode(.template)
                        .foregroundStyle(ChatBubbleMenuStyle.buttonForeground)
                }
                .font(.body)
                .padding(.vertical, ChatBubbleMenuStyle.buttonVerticalPadding)
                .padding(.horizontal, ChatBubbleMenuStyle.buttonHorizontalPadding)
            }
            .frame(width: ChatBubbleMenuStyle.buttonWidth)
            .fixedSize()
            .onTapGesture(perform: action)

            if !config.isAssistant {
                Color.clear.frame(width: ChatBubbleMenuStyle.trailingAlignmentInset)
            }
        }
    }

    // MARK: - Dismiss

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.15)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onDismiss() }
    }
}

// MARK: - Transparent Full Screen Cover

/// 以 `overFullScreen` 样式呈现透明模态，使 `ultraThinMaterial` 能正确模糊底层内容。
extension View {
    func transparentFullScreenCover(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        background(
            TransparentModalPresenter(
                isPresented: isPresented,
                overlayContent: { AnyView(content()) }
            )
        )
    }
}

private struct TransparentModalPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let overlayContent: () -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var hosted: UIHostingController<AnyView>?
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented {
            guard context.coordinator.hosted == nil else { return }
            let hc = UIHostingController(rootView: overlayContent())
            hc.modalPresentationStyle = .overFullScreen
            hc.modalTransitionStyle = .crossDissolve
            hc.view.backgroundColor = .clear
            context.coordinator.hosted = hc
            // 向上找到可用于 present 的最顶层 VC
            var presenting: UIViewController = uiViewController
            while let p = presenting.parent { presenting = p }
            while let already = presenting.presentedViewController { presenting = already }
            presenting.present(hc, animated: false)
        } else {
            guard let hc = context.coordinator.hosted else { return }
            hc.dismiss(animated: false)
            context.coordinator.hosted = nil
        }
    }
}
