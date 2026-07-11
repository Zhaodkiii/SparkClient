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
//            .background(Color(uiColor: .systemBackground))
//            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused || isError ? 1.5 : 1)
            )
            .shadow(
                color: Color.black.opacity(isFocused ? 0.10 : 0.15),
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
extension View {
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
        }
    }
}

// MARK: - Sheet-backed picker row (opens modal / bottom sheet)

/// 标签 + 可点击字段，用于「打开 Bottom Sheet 选择」类交互（药箱剂型、服药频次等）。
struct SparkFormSheetPickerRow: View {
    let title: String
    let displayValue: String
    let placeholder: String
    var required: Bool = false
    var showsValidationError: Bool = false
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if required {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }
            Button {
                onTap()
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Text(resolvedLabel)
                        .font(.body)
                        .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .sparkFormTextFieldChrome(isFocused: false, isError: showsValidationError)
            }
            .buttonStyle(.plain)
        }
    }

    private var trimmedDisplay: String {
        displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPlaceholder: Bool {
        trimmedDisplay.isEmpty
    }

    private var resolvedLabel: String {
        isPlaceholder ? placeholder : displayValue
    }
}

// MARK: - Medication plan reminder frequency (structured + summary text)

enum MedicationReminderFrequencyType: String, CaseIterable, Identifiable, Sendable {
    case daily = "daily"
    case everyNDays = "every_n_days"
    case weekly = "weekly"

    var id: String { rawValue }

    var segmentTitle: String {
        switch self {
        case .daily: return "每天"
        case .everyNDays: return "每几天"
        case .weekly: return "每周"
        }
    }
}

enum MedicationReminderFrequencySummary {
    private static let weekdayOneLetter = ["", "一", "二", "三", "四", "五", "六", "日"]

    fileprivate static func weekdayShortLabel(_ day: Int) -> String {
        switch day {
        case 1: return "一"
        case 2: return "二"
        case 3: return "三"
        case 4: return "四"
        case 5: return "五"
        case 6: return "六"
        case 7: return "日"
        default: return "\(day)"
        }
    }

    static func displayLine(type: MedicationReminderFrequencyType, everyNDays: Int, weekdays: Set<Int>) -> String {
        switch type {
        case .daily:
            return "每天"
        case .everyNDays:
            let n = max(1, everyNDays)
            return "每\(n)天"
        case .weekly:
            let sorted = weekdays.filter { (1...7).contains($0) }.sorted()
            if sorted.isEmpty { return "每周" }
            let labels = sorted.map { weekdayOneLetter[$0] }.joined(separator: "、")
            return "每周 \(labels)"
        }
    }

    static func isComplete(type: MedicationReminderFrequencyType, everyNDays: Int, weekdays: Set<Int>) -> Bool {
        switch type {
        case .daily:
            return true
        case .everyNDays:
            return (1...365).contains(everyNDays)
        case .weekly:
            return weekdays.contains { (1...7).contains($0) }
        }
    }
}

struct MedicationReminderFrequencySheet: View {
    @Environment(\.dismiss) private var dismiss

    let onConfirm: (MedicationReminderFrequencyType, Int, Set<Int>, String) -> Void

    @State private var selectedType: MedicationReminderFrequencyType
    @State private var everyNDays: Int
    @State private var weekdaySet: Set<Int>
    @State private var summaryText: String

    init(
        type: MedicationReminderFrequencyType,
        everyNDays: Int,
        weekdays: Set<Int>,
        summaryText: String,
        onConfirm: @escaping (MedicationReminderFrequencyType, Int, Set<Int>, String) -> Void
    ) {
        self.onConfirm = onConfirm
        let n = min(max(everyNDays, 1), 365)
        _selectedType = State(initialValue: type)
        _everyNDays = State(initialValue: n)
        _weekdaySet = State(initialValue: weekdays)
        _summaryText = State(initialValue: summaryText)
    }

    private var canConfirm: Bool {
        MedicationReminderFrequencySummary.isComplete(
            type: selectedType,
            everyNDays: everyNDays,
            weekdays: weekdaySet
        ) && summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            AdaptiveToolSheetScrollView(bottomContentPadding: 0, extraChromeHeight: 120) {
                VStack(alignment: .leading, spacing: 20) {
                    typeSegment
                    
                    parameterSection
                    
                    
                    SparkFormTextAreaRow(title: "说明（可编辑）", text: $summaryText, minHeight: 80, maxHeight: 160, placeholder: "根据上方选择自动生成，也可修改")

                }
                .padding()
            }
            .navigationTitle("服药频次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel", fallback: "取消")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.done", fallback: "完成")) {
                        let n = min(max(everyNDays, 1), 365)
                        onConfirm(selectedType, n, weekdaySet, summaryText.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(!canConfirm)
                }
                
            }
        }
        .onAppear {
            if summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                applySummaryTemplateIfNeeded()
            }
        }
        .onChange(of: selectedType) { _ in
            applySummaryTemplateIfNeeded()
        }
        .onChange(of: everyNDays) { _ in
            applySummaryTemplateIfNeeded()
        }
        .onChange(of: weekdaySet) { _ in
            applySummaryTemplateIfNeeded()
        }
    }

    private var typeSegment: some View {
        HStack(spacing: 8) {
            ForEach(MedicationReminderFrequencyType.allCases) { t in
                Button {
                    selectedType = t
                } label: {
                    Text(t.segmentTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(selectedType == t ? Color.accentColor : Color.primary)
                        .background(
                            selectedType == t
                                ? Color.accentColor.opacity(0.14)
                                : Color(uiColor: .secondarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var parameterSection: some View {
        switch selectedType {
        case .daily:
            Text("每天服药")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        case .everyNDays:
            VStack(alignment: .leading, spacing: 8) {
                Text("间隔天数")
                    .font(.subheadline.weight(.medium))
                Picker("", selection: $everyNDays) {
                    ForEach(1...365, id: \.self) { n in
                        Text("每 \(n) 天").tag(n)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 180)
                .clipped()
            }
        case .weekly:
            VStack(alignment: .leading, spacing: 10) {
                Text("选择星期（可多选）")
                    .font(.subheadline.weight(.medium))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(1...7, id: \.self) { day in
                        let on = weekdaySet.contains(day)
                        Button {
                            if on {
                                weekdaySet.remove(day)
                            } else {
                                weekdaySet.insert(day)
                            }
                        } label: {
                            Text(MedicationReminderFrequencySummary.weekdayShortLabel(day))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(
                                    on ? Color.accentColor : Color(uiColor: .secondarySystemFill),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func applySummaryTemplateIfNeeded() {
        summaryText = MedicationReminderFrequencySummary.displayLine(
            type: selectedType,
            everyNDays: everyNDays,
            weekdays: weekdaySet
        )
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
    var systemImage: String? = nil
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
        systemImage: String? = nil,
        minHeight: CGFloat = 88,
        maxHeight: CGFloat = 220,
        placeholder: String = "",
        required: Bool = false,
        keyboardVisible: Binding<Bool>? = nil
    ) {
        self.title = title
        _text = text
        self.systemImage = systemImage
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.placeholder = placeholder
        self.required = required
        self.keyboardVisible = keyboardVisible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SparkFormFieldLabel(text: title, systemImage: systemImage, required: required)

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
    var systemImage: String? = nil
    let required: Bool
    init(text: String, systemImage: String? = nil, required: Bool) {
        self.text = text
        self.systemImage = systemImage
        self.required = required
    }

    var body: some View {
        
        if let systemImage {
            Label(text, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
            if required {
                Text("*")
                    .foregroundStyle(.red)
            }
        }else {
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
}

extension String {
    /// 空白字符串视为 `nil`，用于草稿字段映射到可选 API 字段。
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Binding where Value == ItemDraft {
    /// 将 `ItemDraft` 的可选字符串字段绑定为表单用的非可选 `String`。
    func optionalField(_ keyPath: WritableKeyPath<ItemDraft, String?>) -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue[keyPath: keyPath] ?? "" },
            set: { (newValue: String) in
                var draft = self.wrappedValue
                draft[keyPath: keyPath] = newValue.nilIfBlank
                self.wrappedValue = draft
            }
        )
    }
}
