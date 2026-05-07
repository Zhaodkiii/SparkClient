import SwiftUI
import UIKit

/// 病历草稿表单通用容器：标题 + 圆角材质背景，供各 `*FormView` 复用。
struct SparkFormCard<Content: View>: View {
    let title: String
    var titleSystemImage: String?
    @ViewBuilder var content: Content

    init(title: String, titleSystemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleSystemImage = titleSystemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let titleSystemImage {
                    Image(systemName: titleSystemImage)
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(14)
//        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }
}

// MARK: - Single-line text field chrome (system semantic colors; matches `SparkFormTextAreaRow`)

private struct SparkFormTextFieldChrome: ViewModifier {
    let isFocused: Bool
    let isError: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused || isError ? 1.5 : 0)
            )
            .shadow(
                color: Color.primary.opacity(isFocused ? 0.10 : 0.15),
                radius: isFocused ? 8 : 4,
                y: 2
            )
    }

    private var borderColor: Color {
        if isError { return Color(uiColor: .systemRed) }
        if isFocused { return Color.accentColor }
        return Color(uiColor: .separator)
    }
}

private extension View {
    func sparkFormTextFieldChrome(isFocused: Bool, isError: Bool) -> some View {
        modifier(SparkFormTextFieldChrome(isFocused: isFocused, isError: isError))
    }
}

/// 单行 `TextField`，标签在上、输入在下；视觉对齐 Health `FormTextFieldRow`。
struct SparkFormTextRow: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let required: Bool
    /// 与底部条 `sparkFormBottomBar(keyboardVisible:)` 等联动：聚焦时为 `true`，失焦为 `false`。为 `nil` 时在键盘 accessory 显示「完成」。
    var keyboardVisible: Binding<Bool>?

    @FocusState private var isTextFieldFocused: Bool

    init(
        title: String,
        text: Binding<String>,
        placeholder: String = "",
        required: Bool = false,
        keyboardVisible: Binding<Bool>? = nil
    ) {
        self.title = title
        _text = text
        self.placeholder = placeholder
        self.required = required
        self.keyboardVisible = keyboardVisible
    }

    private var resolvedPlaceholder: String {
        placeholder.isEmpty ? title : placeholder
    }

    private var trimmedEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isError: Bool {
        required && trimmedEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SparkFormFieldLabel(text: title, required: required)

            TextField(resolvedPlaceholder, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.next)
                .focused($isTextFieldFocused)
                .sparkFormTextFieldChrome(isFocused: isTextFieldFocused, isError: isError)
                .onChange(of: isTextFieldFocused) { focused in
                    keyboardVisible?.wrappedValue = focused
                }
//                .toolbar {
//                    if #available(iOS 16.0, *) {
//                        if keyboardVisible == nil, isTextFieldFocused {
//                            ToolbarItemGroup(placement: .keyboard) {
//                                Spacer()
//                                Button(L10n.text("common.done")) {
//                                    isTextFieldFocused = false
//                                }
//                            }
//                        }
//                    }
//                }
        }
    }
}

// MARK: - Growing text (UIKit)

private struct SparkFormGrowingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredContentHeight: CGFloat
    @Binding var isEditing: Bool
    var keyboardVisible: Binding<Bool>?
    let isScrollEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        let coordinator = context.coordinator
        coordinator.hostTextView = textView
        textView.delegate = coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = UIColor.systemBackground
        textView.isScrollEnabled = isScrollEnabled
        textView.showsVerticalScrollIndicator = true
        textView.textContainer.lineFragmentPadding = 4
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
//        textView.inputAccessoryView = Self.makeKeyboardAccessoryToolbar(coordinator: coordinator)
        applyInsets(to: textView)
        return textView
    }

//    private static func makeKeyboardAccessoryToolbar(coordinator: Coordinator) -> UIToolbar {
//        let toolbar = UIToolbar()
//        toolbar.sizeToFit()
//        let done = UIBarButtonItem(
//            title: L10n.text("common.done"),
//            style: .done,
//            target: coordinator,
//            action: #selector(Coordinator.doneTapped)
//        )
//        toolbar.items = [
//            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
//            done
//        ]
//        return toolbar
//    }

    private static func makeKeyboardAccessoryToolbar(
        coordinator: Coordinator
    ) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.tintColor = UIColor.secondaryLabel

        // 1. 定义你需要的边距 (上, 左, 下, 右)
        // 如果想彻底贴边，leading/trailing 设置为 0，甚至配合 negative space
        let customInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: 6,
            bottom: 0,
            trailing: 6
        )

        // 2. 配置按钮
        let doneButton = UIButton(type: .system)
        doneButton.setTitle(L10n.text("common.done"), for: .normal)
        doneButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        doneButton.addTarget(coordinator, action: #selector(Coordinator.doneTapped), for: .touchUpInside)

        // 3. 使用 Configuration 精确控制边距
        var config = UIButton.Configuration.plain()
        config.contentInsets = customInsets // 应用上下左右边距
        // 核心代码：将背景配置的圆角设置为 0
        config.background.cornerRadius = 0
        config.background.backgroundColor = .clear
        doneButton.configuration = config

        let doneItem = UIBarButtonItem(customView: doneButton)

        // 4. 处理 Toolbar 容器的系统边距
        // UIToolbar 默认会在左右保留一定的 margin。
        // 如果你发现 leading/trailing 设置为 0 依然有间距，
        // 需要调整 toolbar 的 layoutMargins 或使用负宽度的 fixedSpace。
        let negativeSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        negativeSpace.width = -12 // 这个值通常用来抵消 UIToolbar 默认的横向内缩

        toolbar.items = [
            UIBarButtonItem.flexibleSpace(),
            doneItem,
            negativeSpace
        ]
        
        // 强制让 toolbar 的布局遵循自定义边距
        toolbar.layoutMargins = .zero

        return toolbar
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.hostTextView = uiView
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.isScrollEnabled != isScrollEnabled {
            uiView.isScrollEnabled = isScrollEnabled
            if isScrollEnabled == false, uiView.contentOffset != .zero {
                uiView.setContentOffset(.zero, animated: false)
            }
        }
        applyInsets(to: uiView)
        Self.recalculateContentHeight(view: uiView, result: $measuredContentHeight)
    }

    private func applyInsets(to textView: UITextView) {
        let right: CGFloat = isScrollEnabled ? 28 : 8
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: right)
    }

    private static func recalculateContentHeight(
        view: UITextView,
        result: Binding<CGFloat>
    ) {
        let width = view.bounds.width
        guard width > 8 else { return }
        let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let next = max(fitted, 1)
        if abs(result.wrappedValue - next) > 0.5 {
            DispatchQueue.main.async {
                result.wrappedValue = next
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: SparkFormGrowingTextView
        weak var hostTextView: UITextView?

        init(_ parent: SparkFormGrowingTextView) {
            self.parent = parent
        }

        @objc func doneTapped() {
            hostTextView?.resignFirstResponder()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            SparkFormGrowingTextView.recalculateContentHeight(view: textView, result: parent.$measuredContentHeight)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.isEditing = true
                self.parent.keyboardVisible?.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.isEditing = false
                self.parent.keyboardVisible?.wrappedValue = false
            }
        }

    }
}
// MARK: - VisitDivider

struct VisitDivider: View {
    var color: Color
    var height: CGFloat
    var verticalPadding: CGFloat
    
    init(color: Color = .gray, height: CGFloat = 1, verticalPadding: CGFloat = 4) {
        self.color = color
        self.height = height
        self.verticalPadding = verticalPadding
    }
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: height)
            .padding(.vertical, verticalPadding)
    }
}

/// 多行输入：随内容增高，达到 `maxHeight` 后内部滚动；可展开到 `SparkPromptInputDrawerSheet`。
///
/// 视觉与标签样式对齐 Health `FormTextArea` / `FormLabel`。
struct SparkFormTextAreaRow: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let placeholder: String
    let required: Bool
    var keyboardVisible: Binding<Bool>?

    @State private var measuredContentHeight: CGFloat = 0
    @State private var isEditing = false
    @State private var inputExpandedSheet = false

    private var editorHeight: CGFloat {
        min(max(measuredContentHeight, minHeight), maxHeight)
    }

    /// 内容高度达到上限后启用内部滚动并显示展开按钮。
    private var isScrollable: Bool {
        measuredContentHeight >= maxHeight - 0.5
    }

    init(
        title: String,
        text: Binding<String>,
        minHeight: CGFloat = 88,
        maxHeight: CGFloat = 220,
        placeholder: String = "",
        required: Bool = false,
        keyboardVisible: Binding<Bool>? = nil
    ) {
        self.title = title
        _text = text
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.placeholder = placeholder
        self.required = required
        self.keyboardVisible = keyboardVisible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SparkFormFieldLabel(text: title, required: required)

            SparkFormGrowingTextView(
                text: $text,
                measuredContentHeight: $measuredContentHeight,
                isEditing: $isEditing,
                keyboardVisible: keyboardVisible,
                isScrollEnabled: isScrollable
            )
            .frame(maxWidth: .infinity)
            .frame(height: editorHeight)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isEditing ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Color(.placeholderText))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isScrollable {
                    Button {
                        inputExpandedSheet = true
                    } label: {
                        Image(systemName: "arrow.down.left.and.arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityLabel(L10n.text("medical_record.forms.text_area.expand_editor"))
                }
            }
            .shadow(
                color: Color.primary.opacity(isEditing ? 0.10 : 0.15),
                radius: isEditing ? 8 : 4,
                y: 2
            )

        }
//        .sparkKeyboardDoneToolbar {
//            SparkKeyboardDismiss.endEditing()
//        }
        .sheet(isPresented: $inputExpandedSheet) {
            SparkPromptInputDrawerSheet(
                text: $text,
                isPresented: $inputExpandedSheet
            )
            .sparkInputPresentationChromeIfAvailable()
        }
    }
}

// MARK: - Form label (aligned with Health `FormLabel`)

private struct SparkFormFieldLabel: View {
    let text: String
    let required: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.subheadline.weight(.medium))
            if required {
                Text("*")
                    .foregroundStyle(.red)
            }
        }
    }
}

extension String {
    /// 空白字符串视为 `nil`，用于草稿字段映射到可选 API 字段。
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
